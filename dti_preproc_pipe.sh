#!/bin/bash

'
Preprocesisng pipeline for diffusion-weighted images.

This script will: 

    1) convert your bruker files to nifti
    2) create mask and skull stripping
    3) denoising and eddy correction via FSL
    4) co-registration
    5) calculation of diffusion tensor metrics

NOTE: you need to have installed MRtrix, FSL and ANTs. If you have them in a python enviroment, just activate via conda. 

------

Before you start:

Two variables are hard-coded and need to be modify depending of your dataset:
-> The DTI scan number 
-> First bval number

The script is call with 3 arguments:
1.- The folder containing your bruker files (should only have those files)
2.- The folder you want to put everything else (it will create a new folder depending of what you put in the command line; for example "dti")
3.- The mri_id of the image you want to use as a template to register the bzeros

Then USAGE:
./dti_preproc_pipe <my_path/raw> <my_path/dti> <id_of_ref_img>


PJV
'

##---------- START HERE --------------###

echo 'NOTE: there are a few things hard coded: change it as needed'

dit_id_scan=4 # <- hard coded
first_shell_value=13.4834997087 # <- hard coded 

raw_dir=$1   #my/path/../raw # path to the raw images folder (make sure there is only bruker files in that folder)
out_base=$2 #my/path/../dti #set here the name you want for the output folders (dti, for example)
fixed_img_id=$3   # fixed image ID for registration; chose the one you think is better!

mkdir -p $out_base


# Loop through each Bruker folder
for file in ${raw_dir}/*; do  
    id=$(basename $file | awk -F'_' '{print $3}') 

    echo "Processing MRI ID: $id"
    outdir=${out_base}/${id}
    mkdir -p ${outdir}

    #change it as needed
    dti=${dit_id_scan}

    # -----------------------------------------------------------------
    echo 'STEP 0: Conversion from bruker to nifti'
    # -----------------------------------------------------------------
    nifti_out=${outdir}/${id}_dti.nii.gz
    if [ -f "$nifti_out" ]; then
        echo " Skipp; already exist"
    else

#----NOTE: use below in case there are different scan ids for a particular animal, as an example:
#   case $id in
#     250409)
#         dti=20
#         ;;
#     250415)
#         dti=13
#         ;;
#     250416)
#         dti=12
#         ;;
#     250417)
#         dti=17    
#         ;;
#     esac
#---------------------------------------------------------------------------------------------

        brkraw tonii $file -o ${outdir}/${id}_ -r 1 -s $dti
    fi
  
    # -----------------------------------------------------------------
    echo 'STEP 1: Define paths and variables'
    # -----------------------------------------------------------------
    dwi="${outdir}/${id}_dti.nii.gz"
    bvec=${dwi%.nii.gz}.bvec
    bval=${dwi%.nii.gz}.bval

    working_dwi=$dwi
    working_bvec=$bvec
    working_bval=$bval

    # if [ ! -f "$working_bvec" ] || [ ! -f "$working_bval" ]; then
    #     echo "ERROR: can't find bvec/bvals for $id..."
    #     continue
    # fi

    # change the first b-value to 0
    first_bval=${first_shell_value}  # hardcoded value for first shell; change it as needed
    tmp_bval=${working_bval%.bval}_tmp.bval
    sed "s/${first_bval}/0/g" $working_bval > $tmp_bval && mv $tmp_bval $working_bval

    # -----------------------------------------------------------------
    echo 'STEP 2: Mask'
    # -----------------------------------------------------------------

    fullmask=${outdir}/${id}_fullmask.nii.gz
    if [ ! -f "$fullmask" ]; then
        dwi2mask -fslgrad $working_bvec $working_bval $working_dwi $fullmask
    else
        echo " - Already exist, bye"
    fi

    # -----------------------------------------------------------------
    echo 'STEP 3: Denoise + Eddy'
    # -----------------------------------------------------------------

    dwi_d=${working_dwi%.nii.gz}_d.nii.gz
    if [ ! -f "$dwi_d" ]; then
        dwidenoise $working_dwi $dwi_d
    fi

    eddy_dir=${outdir}/eddy
    mkdir -p $eddy_dir
    dwi_de=${eddy_dir}/${id}_de.nii.gz
    eddy_out=${eddy_dir}/${id}_de

    if [ ! -f "$dwi_de" ]; then
        acqp=${eddy_dir}/acqp.txt
        index=${eddy_dir}/index.txt

        printf "0 -1 0 0.05" > $acqp

        indx=""
        nvols=$(fslnvols $dwi_d)
        for ((i=1; i<=nvols; i++)); do indx="$indx 1"; done
        echo $indx > $index

        eddy diffusion \
            --imain=$dwi_d \
            --mask=$fullmask \
            --acqp=$acqp \
            --index=$index \
            --bvecs=$working_bvec \
            --bvals=$working_bval \
            --data_is_shelled \
            --out=$eddy_out \
            --verbose
    else
        echo " $dwi_de already exist, bye!)"
    fi

    # -----------------------------------------------------------------
    echo 'STEP 4: apply mask before registration'
    # -----------------------------------------------------------------
    
    dwi_dem=${dwi_de%.nii.gz}m.nii.gz

    if [ -f "$dwi_de" ] && [ -f "$fullmask" ]; then
        if [ ! -f "$dwi_dem" ]; then
            mrcalc $dwi_de $fullmask -mul $dwi_dem
        else
            echo " Already exist!"
        fi
    fi

    # -----------------------------------------------------------------
    echo 'STEP 5: Extract mean b0 for registration'
    # -----------------------------------------------------------------
    echo 'STEP 5: extract bzero for registration'

    registdir=${outdir}/registration
    mkdir -p ${registdir}
    b0=${registdir}/${id}_mean_bzero.nii.gz

    if [ ! -f "$b0" ]; then
        dwiextract -fslgrad $working_bvec $working_bval $dwi_dem - -bzero | mrmath - mean $b0 -axis 3
    else
        echo " Already exist :) "
    fi

    # -----------------------------------------------------------------
    echo 'STEP 6: Registration'
    # -----------------------------------------------------------------

    fixed_img=${outdir}/${fixed_img_id}/registration/${fixed_img_id}_mean_bzero.nii.gz
    reg_out=${registdir}/${id}_fulldwi_registered.nii.gz

    if [ -f "$reg_out" ]; then
        echo " - Skipping registration; $reg_out already exist)"
        else

    echo "Registering $id to $fixed_img"
    antsRegistrationSyN.sh \
        -d 3 \
        -f "$fixed_img" \
        -m "$b0" \
        -t br \
        -o ${registdir}/${id}_

    antsApplyTransforms \
        -v 1 -d 3 -e 3 \
        -i "$dwi_dem" \
        -o "$reg_out" \
        -r "$fixed_img" \
        -t ${registdir}/${id}_1Warp.nii.gz \
        -t ${registdir}/${id}_0GenericAffine.mat \
        -n Linear --float
    fi

    # -----------------------------------------------------------------
    echo 'STEP 7: Calculate DTI maps'
    # -----------------------------------------------------------------
    dti_dir=${outdir}/dti_maps
    mkdir -p "$dti_dir"

    tensor=${dti_dir}/tensor.nii.gz
    fa=${dti_dir}/fa.nii.gz
    md=${dti_dir}/md.nii.gz
    rd=${dti_dir}/rd.nii.gz
    ad=${dti_dir}/ad.nii.gz

    dwi2tensor -fslgrad $working_bvec $working_bval $reg_out $tensor
    tensor2metric -fa $fa -adc $md -rd $rd -ad $ad $tensor

    
# --------------------------------------------------------------
# You're DONE :)
# -------------------------------------------------------------- 

done
    


