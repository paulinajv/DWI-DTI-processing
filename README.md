## Preprocesisng pipeline for diffusion-weighted images.

This script will: 

1) convert your bruker files to nifti
2) create mask and skull stripping
3) denoising and eddy correction via FSL
4) co-registration
5) calculation of diffusion tensor metrics

NOTE: you need to have installed MRtrix, FSL and ANTs. If you have them in a python enviroment, just activate via conda. 

Before you start:

One variable is hard-coded and need to be modify depending of your dataset:
- The DTI scan number 


The script is call with 3 arguments:

1) The folder containing your bruker files (should only have those files)
2) The folder you want to put everything else (it will create a new folder depending of what you put in the command line; for example "dti")
3) The mri_id of the image you want to use as a template to register the bzeros

USAGE:

`./dti_preproc_pipe <my_path/raw> <my_path/dti> <id_of_ref_img>`

