
# Exposure Render

Exposure Render is a CUDA based volume raycaster, enhanced with physically based light transport. More information about the rendering algorithm can be found here:
* [An interactive photo-realistic volume rendering framework](http://graphics.tudelft.nl/Publications/kroes_exposure_2012)  
T. Kroes, F. H. Post, C. P. Botha
* [Visibility sweeps for joint-hierarchical importance sampling of direct lighting for stochastic volume rendering](http://graphics.tudelft.nl/Publications-new/2015/KEE1)  
T. Kroes, M. Eisemann, E. Eisemann

The latest windows executable can be found [here](https://github.com/ThomasKroes/exposure-render/releases/tag/1.1.0)

![https://graphics.tudelft.nl/publications/](/Images/manix.png)

## Building Exposure Render from source code
If you are eager to build Exposure Render yourself you should clone the [release110](https://github.com/ThomasKroes/exposure-render.release110.git) repository and follow  [these](https://github.com/ThomasKroes/exposure-render.release110/blob/master/build.md) instructions .

## System requirements

* Microsoft Windows XP, Vista, or 7.
* At least 1GB of system memory.
* NVIDIA CUDA-compatible GPU with compute capability 1.0 and at least 512 megabytes of DRAM. GTX270 or higher is recommended
* At the moment, larger data sets might give problems, we are working on that!

## Developer(s)

Thomas Kroes

Affiliations:

**Delft University of Technology (TU Delft)**  
Computer Graphics and Visualization (CGV)  
*t.kroes at tudelft.nl*

**Leids Universitair medisch centrum (LUMC)**  
Laboratorium voor Klinische en Experimentele Beeldverwerking (LKEB)  
*t.kroes at lumc.nl*

## Acknowledgements

* Osirix Imaging Software for sharing the medical data sets
* Volvis website for the engine and bonsai data set
* Fugue icons for the icon database

## Tested system configurations

Exposure Render has been tested on the following system configurations using Nvidia hardware:

* Windows 7 (64 bit) + Quadro FX1700
* Windows 7 (64 bit) + GTS240
* Windows 7 (64 bit) + GTS250
* Windows 7 (64 bit) + GTS450
* Windows 7 (64 bit) + GTX260
* Windows 7 (64 bit) + GTX270
* Windows 7 (64 bit) + GTX460
* Windows 7 (64 bit) + GTX470
* Windows 7 (64 bit) + GTX560
* Windows 7 (64 bit) + GTX570
* Windows 7 (64 bit) + GTX580

*Please mention your complete system setup when you report a bug: (OS (32/64 bit), graphics card, driver version etc.), possibly along with screen shots and error messages. Help make Exposure Render stable!*
