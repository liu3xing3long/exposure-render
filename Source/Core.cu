/*
	Copyright (c) 2011, T. Kroes <t.kroes@tudelft.nl>
	All rights reserved.

	Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

	- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
	- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
	- Neither the name of the TU Delft nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
	
	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include <thrust/reduce.h>

#include "General.cuh"

ExposureRender::KernelTimings gKernelTimings;

#include "Core.cuh"
#include "CudaUtilities.cuh"
#include "Framebuffer.cuh"
#include "Benchmark.cuh"
#include "Filter.cuh"
#include "Tracer.cuh"

texture<unsigned short, cudaTextureType3D, cudaReadModeNormalizedFloat>		gTexIntensity;
texture<float, cudaTextureType1D, cudaReadModeElementType>					gTexOpacity;
texture<float4, cudaTextureType1D, cudaReadModeElementType>					gTexDiffuse;
texture<float4, cudaTextureType1D, cudaReadModeElementType>					gTexSpecular;
texture<float, cudaTextureType1D, cudaReadModeElementType>					gTexGlossiness;
texture<float4, cudaTextureType1D, cudaReadModeElementType>					gTexEmission;

cudaArray* gpIntensity	= NULL;
cudaArray* gpOpacity	= NULL;
cudaArray* gpDiffuse	= NULL;
cudaArray* gpSpecular	= NULL;
cudaArray* gpGlossiness	= NULL;
cudaArray* gpEmission	= NULL;

CD ExposureRender::Camera								gCamera;
CD ExposureRender::Lights								gLights;
CD ExposureRender::Objects								gObjects;
CD ExposureRender::ClippingObjects						gClippingObjects;
CD ExposureRender::Textures								gTextures;
CD ExposureRender::RenderSettings						gRenderSettings;
CD ExposureRender::Range								gOpacityRange;
CD ExposureRender::Range								gDiffuseRange;
CD ExposureRender::Range								gSpecularRange;
CD ExposureRender::Range								gGlossinessRange;
CD ExposureRender::Range								gEmissionRange;
CD ExposureRender::GaussianFilter						gFrameEstimateFilter;
CD ExposureRender::BilateralFilter						gPostProcessingFilter;

ExposureRender::FrameBuffer								gFrameBuffer;

__device__ ExposureRender::Tracer* gpTracer;

ExposureRender::Tracer gTracer;

static std::map<int, ExposureRender::Texture>			gTextureMap;
static std::map<int, ExposureRender::Light>				gLightsMap;
static std::map<int, ExposureRender::Object>			gObjectsMap;
static std::map<int, ExposureRender::ClippingObject>	gClippingObjectsMap;

int	gNoIterations = 0;

#include "GaussianFilter.cuh"
#include "BilateralFilter.cuh"
#include "MedianFilter.cuh"
#include "Estimate.cuh"
#include "Utilities.cuh"
#include "SingleScattering.cuh"
#include "Metropolis.cuh"
#include "ToneMap.cuh"
#include "Blend.cuh"
#include "GradientMagnitude.cuh"
#include "AutoFocus.cuh"

namespace ExposureRender
{

EXPOSURE_RENDER_DLL void Resize(int Size[2])
{
	gFrameBuffer.Resize(Resolution2i(Size));
}

EXPOSURE_RENDER_DLL void Reset()
{
	gFrameBuffer.Reset();
	gNoIterations = 0;
}

EXPOSURE_RENDER_DLL void BindVolume(int Resolution[3], float Spacing[3], float Range[2], unsigned short* pVoxels, bool NormalizeSize)
{
	gTracer.Volume.Set(Vec3f(Resolution[0], Resolution[1], Resolution[2]), Vec3f(Spacing[0], Spacing[1], Spacing[2]), Range, pVoxels, NormalizeSize);

	Tracer* pTracer = NULL;

	cudaMalloc(&pTracer, sizeof(Tracer));
	cudaMemcpy(pTracer, &gTracer, sizeof(Tracer), cudaMemcpyHostToDevice);
	cudaMemcpyToSymbol(gpTracer, &pTracer, sizeof(pTracer));
}

EXPOSURE_RENDER_DLL void UnbindOpacity1D(void)
{
	CUDA::FreeArray(gpOpacity);
	CUDA::UnbindTexture(gTexOpacity);
}

EXPOSURE_RENDER_DLL void UnbindDiffuse1D(void)
{
	CUDA::FreeArray(gpDiffuse);
	CUDA::UnbindTexture(gTexDiffuse);
}

EXPOSURE_RENDER_DLL void UnbindSpecular1D(void)
{
	CUDA::FreeArray(gpSpecular);
	CUDA::UnbindTexture(gTexSpecular);
}

EXPOSURE_RENDER_DLL void UnbindGlossiness1D(void)
{
	CUDA::FreeArray(gpGlossiness);
	CUDA::UnbindTexture(gTexGlossiness);
}

EXPOSURE_RENDER_DLL void UnbindEmission1D(void)
{
	CUDA::FreeArray(gpEmission);
	CUDA::UnbindTexture(gTexEmission);
}

EXPOSURE_RENDER_DLL void BindOpacity1D(float Opacity[NO_TF_STEPS], float IntensityRange[2])
{
	UnbindOpacity1D();

	Range Int;
	Int.Set(IntensityRange);

	CUDA::HostToConstantDevice(&Int, "gOpacityRange"); 
	CUDA::BindTexture1D(gTexOpacity, NO_TF_STEPS, Opacity, gpOpacity);
}

EXPOSURE_RENDER_DLL void BindDiffuse1D(float Diffuse[3][NO_TF_STEPS], float IntensityRange[2])
{
	UnbindDiffuse1D();

	Range Int;
	Int.Set(IntensityRange);

	CUDA::HostToConstantDevice(&Int, "gDiffuseRange");

	ColorXYZAf DiffuseXYZA[NO_TF_STEPS];

	for (int i = 0; i < NO_TF_STEPS; i++)
		DiffuseXYZA[i].FromRGB(Diffuse[0][i], Diffuse[1][i], Diffuse[2][i]);

	CUDA::BindTexture1D(gTexDiffuse, NO_TF_STEPS, (float4*)DiffuseXYZA, gpDiffuse);
}

EXPOSURE_RENDER_DLL void BindSpecular1D(float Specular[3][NO_TF_STEPS], float IntensityRange[2])
{
	UnbindSpecular1D();

	Range Int;
	Int.Set(IntensityRange);

	CUDA::HostToConstantDevice(&Int, "gSpecularRange");

	ColorXYZAf SpecularXYZA[NO_TF_STEPS];

	for (int i = 0; i < NO_TF_STEPS; i++)
		SpecularXYZA[i].FromRGB(Specular[0][i], Specular[1][i], Specular[2][i]);

	CUDA::BindTexture1D(gTexSpecular, NO_TF_STEPS, (float4*)SpecularXYZA, gpSpecular);
}

EXPOSURE_RENDER_DLL void BindGlossiness1D(float Glossiness[NO_TF_STEPS], float IntensityRange[2])
{
	UnbindGlossiness1D();

	Range Int;
	Int.Set(IntensityRange);

	for (int i = 0; i < NO_TF_STEPS; i++)
		Glossiness[i] = GlossinessExponent(Glossiness[i]);

	CUDA::HostToConstantDevice(&Int, "gGlossinessRange");
	CUDA::BindTexture1D(gTexGlossiness, NO_TF_STEPS, Glossiness, gpGlossiness);
}

EXPOSURE_RENDER_DLL void BindEmission1D(float Emission[3][NO_TF_STEPS], float IntensityRange[2])
{
	UnbindEmission1D();

	Range Int;
	Int.Set(IntensityRange);

	CUDA::HostToConstantDevice(&Int, "gEmissionRange");

	ColorXYZAf EmissionXYZA[NO_TF_STEPS];

	for (int i = 0; i < NO_TF_STEPS; i++)
		EmissionXYZA[i].FromRGB(Emission[0][i], Emission[1][i], Emission[2][i]);

	CUDA::BindTexture1D(gTexEmission, NO_TF_STEPS, (float4*)EmissionXYZA, gpEmission);
}

EXPOSURE_RENDER_DLL void BindCamera(Camera* pCamera)
{
	const Vec3f N = Normalize(ToVec3f(pCamera->Target) - ToVec3f(pCamera->Pos));
	const Vec3f U = Normalize(Cross(N, ToVec3f(pCamera->Up)));
	const Vec3f V = Normalize(Cross(N, U));

	pCamera->N[0] = N[0];
	pCamera->N[1] = N[1];
	pCamera->N[2] = N[2];
	pCamera->U[0] = U[0];
	pCamera->U[1] = U[1];
	pCamera->U[2] = U[2];
	pCamera->V[0] = V[0];
	pCamera->V[1] = V[1];
	pCamera->V[2] = V[2];

	if (pCamera->FocalDistance == -1.0f)
		pCamera->FocalDistance = (ToVec3f(pCamera->Target) - ToVec3f(pCamera->Pos)).Length();

	float Scale = 0.0f;

	Scale = tanf((0.5f * pCamera->FOV / RAD_F));

	const float AspectRatio = (float)pCamera->FilmHeight / (float)pCamera->FilmWidth;

	if (AspectRatio > 1.0f)
	{
		pCamera->Screen[0][0] = -Scale;
		pCamera->Screen[0][1] = Scale;
		pCamera->Screen[1][0] = -Scale * AspectRatio;
		pCamera->Screen[1][1] = Scale * AspectRatio;
	}
	else
	{
		pCamera->Screen[0][0] = -Scale / AspectRatio;
		pCamera->Screen[0][1] = Scale / AspectRatio;
		pCamera->Screen[1][0] = -Scale;
		pCamera->Screen[1][1] = Scale;
	}

	pCamera->InvScreen[0] = (pCamera->Screen[0][1] - pCamera->Screen[0][0]) / (float)pCamera->FilmWidth;
	pCamera->InvScreen[1] = (pCamera->Screen[1][1] - pCamera->Screen[1][0]) / (float)pCamera->FilmHeight;

	CUDA::HostToConstantDevice(pCamera, "gCamera");
}

EXPOSURE_RENDER_DLL void BindLight(Light* pLight)
{
	if (!pLight)
		throw(Exception("Light", "Invalid light pointer!"));
	
	std::map<int, ExposureRender::Light>::iterator It;

	It = gLightsMap.find(pLight->ID);

	gLightsMap[pLight->ID] = *pLight;

	ExposureRender::Lights Lights;

	for (It = gLightsMap.begin(); It != gLightsMap.end(); It++)
	{
		if (It->second.Enabled)
		{
			Lights.List[Lights.Count] = It->second;
			
			Shape& Shape = Lights.List[Lights.Count].Shape;

			switch (Shape.Type)
			{
				case Enums::Plane:		Shape.Area = PlaneArea(Vec2f(Shape.Size[0], Shape.Size[1]));				break;
				case Enums::Disk:		Shape.Area = DiskArea(Shape.OuterRadius);									break;
				case Enums::Ring:		Shape.Area = RingArea(Shape.OuterRadius, Shape.InnerRadius);				break;
				case Enums::Box:		Shape.Area = BoxArea(Vec3f(Shape.Size[0], Shape.Size[1], Shape.Size[2]));	break;
				case Enums::Sphere:		Shape.Area = SphereArea(Shape.OuterRadius);									break;
				case Enums::Cylinder:	Shape.Area = CylinderArea(Shape.OuterRadius, Shape.Size[2]);				break;
			}

			Lights.Count++;
		}
	}

	CUDA::HostToConstantDevice(&Lights, "gLights"); 
}

EXPOSURE_RENDER_DLL void UnbindLight(Light* pLight)
{
	if (!pLight)
		throw(Exception("Light", "Invalid light pointer!"));

	std::map<int, ExposureRender::Light>::iterator It;

	It = gLightsMap.find(pLight->ID);

	if (It == gLightsMap.end())
		return;

	gLightsMap.erase(It);

	ExposureRender::Lights Lights;

	for (It = gLightsMap.begin(); It != gLightsMap.end(); It++)
	{
		if (It->second.Enabled)
		{
			Lights.List[Lights.Count] = It->second;
			Lights.Count++;
		}
	}

	CUDA::HostToConstantDevice(&Lights, "gLights");
}

EXPOSURE_RENDER_DLL void BindObject(Object* pObject)
{
	if (!pObject)
		throw(Exception("Object", "Invalid object pointer!"));
	
	std::map<int, ExposureRender::Object>::iterator It;

	It = gObjectsMap.find(pObject->ID);

	gObjectsMap[pObject->ID] = *pObject;

	ExposureRender::Objects Objects;

	for (It = gObjectsMap.begin(); It != gObjectsMap.end(); It++)
	{
		if (It->second.Enabled)
		{
			Objects.List[Objects.Count] = It->second;
			Objects.Count++;
		}
	}

	CUDA::HostToConstantDevice(&Objects, "gObjects"); 
}

EXPOSURE_RENDER_DLL void UnbindObject(Object* pObject)
{
	if (!pObject)
		throw(Exception("Object", "Invalid object pointer!"));

	std::map<int, ExposureRender::Object>::iterator It;

	It = gObjectsMap.find(pObject->ID);

	if (It == gObjectsMap.end())
		return;

	gObjectsMap.erase(It);

	ExposureRender::Objects Objects;

	for (It = gObjectsMap.begin(); It != gObjectsMap.end(); It++)
	{
		if (It->second.Enabled)
		{
			Objects.List[Objects.Count] = It->second;
			Objects.Count++;
		}
	}

	CUDA::HostToConstantDevice(&Objects, "gObjects");
}

EXPOSURE_RENDER_DLL void BindClippingObject(ClippingObject* pClippingObject)
{
	if (!pClippingObject)
		throw(Exception("Clipping Object", "Invalid clipping object pointer!"));
	
	std::map<int, ExposureRender::ClippingObject>::iterator It;

	It = gClippingObjectsMap.find(pClippingObject->ID);

	gClippingObjectsMap[pClippingObject->ID] = *pClippingObject;

	ExposureRender::ClippingObjects ClippingObjects;

	for (It = gClippingObjectsMap.begin(); It != gClippingObjectsMap.end(); It++)
	{
		if (It->second.Enabled)
		{
			ClippingObjects.List[ClippingObjects.Count] = It->second;
			ClippingObjects.Count++;
		}
	}

	CUDA::HostToConstantDevice(&ClippingObjects, "gClippingObjects"); 
}

EXPOSURE_RENDER_DLL void UnbindClippingObject(ClippingObject* pClippingObject)
{
	if (!pClippingObject)
		throw(Exception("Clipping Object", "Invalid clipping object pointer!"));

	std::map<int, ExposureRender::ClippingObject>::iterator It;

	It = gClippingObjectsMap.find(pClippingObject->ID);

	if (It == gClippingObjectsMap.end())
		return;

	gClippingObjectsMap.erase(It);

	ExposureRender::ClippingObjects ClippingObjects;

	for (It = gClippingObjectsMap.begin(); It != gClippingObjectsMap.end(); It++)
	{
		if (It->second.Enabled)
		{
			ClippingObjects.List[ClippingObjects.Count] = It->second;
			ClippingObjects.Count++;
		}
	}

	CUDA::HostToConstantDevice(&ClippingObjects, "gClippingObjects");
}

EXPOSURE_RENDER_DLL void BindRenderSettings(RenderSettings* pRenderSettings)
{
	CUDA::HostToConstantDevice(pRenderSettings, "gRenderSettings");
}

EXPOSURE_RENDER_DLL void BindFiltering(Filtering* pFiltering)
{
	// Frame estimate filter
	GaussianFilter Gaussian;
	
	Gaussian.KernelRadius = pFiltering->FrameEstimateFilter.KernelRadius;

	const int KernelSize = (2 * Gaussian.KernelRadius) + 1;

	for (int i = 0; i < KernelSize; i++)
		Gaussian.KernelD[i] = Gauss2D(pFiltering->FrameEstimateFilter.Sigma, Gaussian.KernelRadius - i, 0);

	CUDA::HostToConstantDevice(&Gaussian, "gFrameEstimateFilter");

	// Post processing filter
	BilateralFilter Bilateral;

	const int SigmaMax = (int)max(pFiltering->PostProcessingFilter.SigmaD, pFiltering->PostProcessingFilter.SigmaR);
	
	Bilateral.KernelRadius = (int)ceilf(2.0f * (float)SigmaMax);  

	const float TwoSigmaRSquared = 2 * pFiltering->PostProcessingFilter.SigmaR * pFiltering->PostProcessingFilter.SigmaR;

	const int kernelSize = Bilateral.KernelRadius * 2 + 1;
	const int center = (kernelSize - 1) / 2;

	for (int x = -center; x < -center + kernelSize; x++)
		Bilateral.KernelD[x + center] = Gauss2D(pFiltering->PostProcessingFilter.SigmaD, x, 0);

	for (int i = 0; i < 256; i++)
		Bilateral.GaussSimilarity[i] = expf(-((float)i / TwoSigmaRSquared));

	CUDA::HostToConstantDevice(&Bilateral, "gPostProcessingFilter");
}

EXPOSURE_RENDER_DLL void BindTexture(Texture* pTexture)
{
	if (!pTexture)
		throw(Exception("Texture", "Invalid texture pointer!"));
	
	std::map<int, ExposureRender::Texture>::iterator It;

	It = gTextureMap.find(pTexture->ID);

	const bool Exists = It != gTextureMap.end();

	gTextureMap[pTexture->ID] = *pTexture;

	if (pTexture->Image.Dirty)
	{
		if (gTextureMap[pTexture->ID].Image.pData)
			CUDA::Free(gTextureMap[pTexture->ID].Image.pData);

		if (pTexture->Image.pData)
		{
			const int NoPixels = gTextureMap[pTexture->ID].Image.Size[0] * gTextureMap[pTexture->ID].Image.Size[1];
		
			CUDA::Allocate(gTextureMap[pTexture->ID].Image.pData, NoPixels);
			CUDA::MemCopyHostToDevice(pTexture->Image.pData, gTextureMap[pTexture->ID].Image.pData, NoPixels);
		}
	} 

	ExposureRender::Textures Textures;

	for (It = gTextureMap.begin(); It != gTextureMap.end(); It++)
	{
		Textures.List[Textures.Count] = It->second;
		Textures.List[Textures.Count].Image.pData = It->second.Image.pData;
		Textures.Count++;
	}

	CUDA::HostToConstantDevice(&Textures, "gTextures");
}

EXPOSURE_RENDER_DLL void UnbindTexture(Texture* pTexture)
{
	if (!pTexture)
		throw(Exception("Texture", "Invalid texture pointer!"));

	std::map<int, ExposureRender::Texture>::iterator It;

	It = gTextureMap.find(pTexture->ID);

	if (It == gTextureMap.end())
		return;

	if (It->second.Image.pData)
		CUDA::Free(It->second.Image.pData);

	gTextureMap.erase(It);

	ExposureRender::Textures Textures;

	for (It = gTextureMap.begin(); It != gTextureMap.end(); It++)
	{
		Textures.List[Textures.Count] = It->second;
		Textures.Count++;
	}

	CUDA::HostToConstantDevice(&Textures, "gTextures"); 
}

EXPOSURE_RENDER_DLL void UnbindAllTextures()
{
	std::map<int, ExposureRender::Texture>::iterator It;

	for (It = gTextureMap.begin(); It != gTextureMap.end(); It++)
	{
		if (It->second.Image.pData)
		CUDA::Free(It->second.Image.pData);
	}

	gTextureMap.clear();

	ExposureRender::Textures Textures;
	CUDA::HostToConstantDevice(&Textures, "gTextures");
}

EXPOSURE_RENDER_DLL void RenderEstimate()
{
	gKernelTimings.Reset();

	FrameBuffer* pDevFrameBuffer = NULL;

	CUDA::Allocate(pDevFrameBuffer);
	CUDA::MemCopyHostToDevice(&gFrameBuffer, pDevFrameBuffer);

	CUDA::ThreadSynchronize();

	SingleScattering(pDevFrameBuffer, gFrameBuffer.Resolution[0], gFrameBuffer.Resolution[1]);
	FilterGaussian(gFrameBuffer.CudaFrameEstimate.GetPtr(), gFrameBuffer.CudaFrameEstimateTemp.GetPtr(), gFrameBuffer.Resolution[0], gFrameBuffer.Resolution[1]);
	ComputeEstimate(pDevFrameBuffer, gFrameBuffer.Resolution[0], gFrameBuffer.Resolution[1]);
	ToneMap(pDevFrameBuffer, gFrameBuffer.Resolution[0], gFrameBuffer.Resolution[1]);
//	FilterBilateral(gFrameBuffer.CudaDisplayEstimate.GetPtr(), gFrameBuffer.CudaDisplayEstimateTemp.GetPtr(), gFrameBuffer.CudaDisplayEstimateFiltered.GetPtr(), gFrameBuffer.Resolution[0], gFrameBuffer.Resolution[1]);
//	MedianFilter(gFrameBuffer.CudaDisplayEstimate.GetPtr(), gFrameBuffer.CudaDisplayEstimateFiltered.GetPtr(), gFrameBuffer.Resolution[0], gFrameBuffer.Resolution[1]);
//	Blend(gFrameBuffer.CudaDisplayEstimate.GetPtr(), gFrameBuffer.CudaDisplayEstimateFiltered.GetPtr(), gFrameBuffer.Resolution[0], gFrameBuffer.Resolution[1]);

	CUDA::Free(pDevFrameBuffer);

	CUDA::ThreadSynchronize();

	gNoIterations++;
}

EXPOSURE_RENDER_DLL void GetEstimate(unsigned char* pData)
{
	CUDA::MemCopyDeviceToHost(gFrameBuffer.CudaDisplayEstimate.GetPtr(), (ColorRGBAuc*)pData, gFrameBuffer.CudaDisplayEstimate.GetNoElements());
}

EXPOSURE_RENDER_DLL void RecordBenchmarkImage()
{
//	CUDA::MemCopyDeviceToDevice(gFrameBuffer.CudaDisplayEstimate.GetPtr(), gFrameBuffer.BenchmarkEstimateRgbaLdr.GetPtr(), gFrameBuffer.CudaDisplayEstimate.GetNoElements()); 
}

EXPOSURE_RENDER_DLL void GetAverageNrmsError(float& AverageNrmsError)
{
	FrameBuffer* pDevFrameBuffer = NULL;
	CUDA::Allocate(pDevFrameBuffer);
	CUDA::MemCopyHostToDevice(&gFrameBuffer, pDevFrameBuffer);

	ComputeAverageNrmsError(gFrameBuffer, pDevFrameBuffer, gFrameBuffer.Resolution[0], gFrameBuffer.Resolution[1], AverageNrmsError);

	CUDA::Free(pDevFrameBuffer);
}

EXPOSURE_RENDER_DLL void GetMaximumGradientMagnitude(float& MaximumGradientMagnitude, int Extent[3])
{
	ComputeGradientMagnitudeVolume(Extent, MaximumGradientMagnitude);
}

EXPOSURE_RENDER_DLL void GetAutoFocusDistance(int FilmU, int FilmV, float& AutoFocusDistance)
{
	ComputeAutoFocusDistance(FilmU, FilmV, AutoFocusDistance);
}

EXPOSURE_RENDER_DLL void GetKernelTimings(KernelTimings* pKernelTimings)
{
	if (!pKernelTimings)
		return;

	*pKernelTimings = gKernelTimings;
}

EXPOSURE_RENDER_DLL void GetMemoryUsed(float& MemoryUsed)
{
	/*
	CUsize_t free = 0;
    CUsize_t total = 0;
    cuMemGetInfo(&free, &total);
    return total - free;
	*/ 
}

EXPOSURE_RENDER_DLL void GetNoIterations(int& NoIterations)
{
	NoIterations = gNoIterations; 
}

EXPOSURE_RENDER_DLL void Deinitialize()
{
	UnbindOpacity1D();
	UnbindDiffuse1D();
	UnbindSpecular1D();
	UnbindGlossiness1D();
	UnbindEmission1D();
	UnbindAllTextures();

	gFrameBuffer.Free();
}

EXPOSURE_RENDER_DLL void Initialize()
{
	Deinitialize();

	ExposureRender::Lights Lights;
	CUDA::HostToConstantDevice(&Lights, "gLights");
}

}