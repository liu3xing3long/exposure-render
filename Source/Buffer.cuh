/*
	Copyright (c) 2011, T. Kroes <t.kroes@tudelft.nl>
	All rights reserved.

	Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

	- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
	- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
	- Neither the name of the <ORGANIZATION> nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
	
	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#pragma once

#include "Geometry.h"
#include "CudaUtilities.h"

template<class T>
class CCudaBuffer2D
{
public:
	CCudaBuffer2D(void) :
		m_Resolution(0, 0),
		m_pData(NULL)
	{
	}

	virtual ~CCudaBuffer2D(void)
	{
		Free();
	}

	CCudaBuffer2D::CCudaBuffer2D(const CCudaBuffer2D& Other)
	{
		*this = Other;
	}

	CCudaBuffer2D& CCudaBuffer2D::operator=(const CCudaBuffer2D& Other)
	{
		m_Resolution	= Other.m_Resolution;
		m_pData			= Other.m_pData;

		return *this;
	}

	void Resize(const CResolution2D& Resolution)
	{
		m_Resolution = Resolution;

		Free();

		HandleCudaError(cudaMalloc(&m_pData, m_Resolution.GetNoElements() * sizeof(T)), "Reset Cuda Buffer");
	}

	void Reset(void)
	{
//		const int Size = m_Resolution.GetNoElements() * sizeof(T);
//		HandleCudaError(cudaMemset(m_pData, 0, Size), "Reset Cuda Buffer");
	}

	void Free(void)
	{
		HandleCudaError(cudaFree(m_pData), "Free Cuda Buffer");
		m_pData = NULL;
	}

	T Read(const int& X, const int& Y)
	{
		return m_pData[Y * m_Resolution.GetResX() + X];
	}

	void Write(const int& X, const int& Y)
	{
	}

	int GetNoElements(void) const
	{
		return m_Resolution.GetNoElements();
	}

	int GetSize(void) const
	{
		return GetNoElements() * sizeof(T);
	}

	CResolution2D	m_Resolution;
	T*				m_pData;
};

class CCudaRandomBuffer2D : public CCudaBuffer2D<unsigned int>
{
public:
	void Resize(const CResolution2D& Resolution)
	{
		CCudaBuffer2D::Resize(Resolution);

		// Create random seeds
		unsigned int* pSeeds = (unsigned int*)malloc(GetSize());

		memset(pSeeds, 0, GetSize());

		for (int i = 0; i < GetNoElements(); i++)
			pSeeds[i] = rand();

		HandleCudaError(cudaMemcpy(m_pData, pSeeds, GetSize(), cudaMemcpyHostToDevice));

		free(pSeeds);
	}
};

template<class T>
class CCudaBuffer3D
{
public:
	CCudaBuffer3D(void) :
		m_Resolution(),
		m_pData(NULL)
	{
	}

	virtual ~CCudaBuffer3D(void)
	{
		Free();
	}

	CCudaBuffer3D::CCudaBuffer3D(const CCudaBuffer3D& Other)
	{
		*this = Other;
	}

	CCudaBuffer3D& CCudaBuffer3D::operator=(const CCudaBuffer3D& Other)
	{
		m_Resolution	= Other.m_Resolution;
		m_pData			= Other.m_pData;

		return *this;
	}

	void Resize(const CResolution3D& Resolution)
	{
		m_Resolution = Resolution;

		Free();

		HandleCudaError(cudaMalloc(&m_pData, GetSize()), "Resize Cuda Buffer");
	}

	void BindRawData(T* pData, const CResolution3D& Resolution)
	{
		Resize(Resolution);

		HandleCudaError(cudaMemcpy(m_pData, (void*)pData, GetSize(), cudaMemcpyHostToDevice), "Resize Cuda Buffer");
	}

	void Free(void)
	{
		if (m_pData == NULL)
			return;

		HandleCudaError(cudaFree(m_pData), "Free Cuda Buffer");
		m_pData = NULL;
	}

	int GetNoElements(void) const
	{
		return m_Resolution.GetNoElements();
	}

	int GetSize(void) const
	{
		return GetNoElements() * sizeof(T);
	}

	/*
	float Get(const int& x, const int& y, const int& z) const
	{
        x = Clamp(x, 0, nx - 1);
        y = Clamp(y, 0, ny - 1);
        z = Clamp(z, 0, nz - 1);

        return density[z*nx*ny + y*nx + x];
    }
	*/

	CResolution3D	m_Resolution;
	T*				m_pData;
};