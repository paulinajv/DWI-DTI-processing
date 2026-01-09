#!/bin/bash

##---------- START HERE --------------###

echo 'NOTE: there are a few things hard coded: change it as needed'

dit_id_scan=4 # <- hard coded

basedir=$1
raw_dir=$2   #my/path/../raw # path to the raw images folder (make sure there is only bruker files in that folder)
out_base=$3 #my/path/../dti #set here the name you want for the output folders (dti, for example)

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
    dwi="${outdir}/${id}_*.nii.gz"
    bvec="${dwi%.nii.gz}.bvec"
    bval="${dwi%.nii.gz}.bval"

    working_dwi=${outdir}/${id}_dti.nii.gz
    working_bvec=${working_dwi%.nii.gz}.bvec
    working_bval=${working_dwi%.nii.gz}.bval

    echo $dwi
    echo $bvec
    echo $bval 

    if [ -f "$working_dwi" ] && [ -f "$working_bvec" ] && [ -f "$working_bval" ]; then
    echo " - Skipping STEP 1 for $id (files already exist)"
    else
    echo " - Moving and renaming files for $id ..."
    mv $dwi $working_dwi
    mv $bval $working_bval
    mv $bvec $working_bvec

    if [ ! -f "$working_bvec" ] || [ ! -f "$working_bval" ]; then
        echo "ERROR: can't find bvec/bvals for $id..."
        continue
    fi

    # --- change the first b-value to 0 ---
    first_bval=$(cat $working_bval | awk '{print $1}')
    echo $first_bval
    tmp_bval=${working_bval%.bval}_tmp.bval
    sed "s/${first_bval}/0/g" "$working_bval" > "$tmp_bval" 
    fi
    
    cp $tmp_bval $working_bval #copy back the corrected bval, keep old just in case

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
    dwi_de=${eddy_dir}/${id}_dti_de.nii.gz
    eddy_out=${eddy_dir}/${id}_dti_de

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
    
    # copy the eddy bvecs
    rotated_bvecs=${outdir}/${id}_dti_rotated.bvec

    if [ ! -f "$rotated_bvecs" ]; then
        cp "${eddy_dir}/${id}_dti_de.eddy_rotated_bvecs" "$rotated_bvecs"
    else
        echo " rotated bvecs file exists "
    fi
    # make sure we replace any -na or -nan values with 0
    if grep -qE -- '-na|-nan' "$rotated_bvecs"; then
    sed -i 's/-na\{0,10\}/0/g' "$rotated_bvecs"
    echo "Replaced -na/-nan with 0 in rotated bvecs"
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

    registdir=${outdir}/registration
    mkdir -p ${registdir}
    b0=${registdir}/${id}_mean_bzero.nii.gz

    if [ ! -f "$b0" ]; then
        dwiextract -fslgrad $rotated_bvecs $working_bval $dwi_dem - -bzero | mrmath - mean $b0 -axis 3
    else
        echo " Already exist :) "
    fi

    # -----------------------------------------------------------------
    echo 'STEP 6: Calculate DTI maps'
    # -----------------------------------------------------------------
   
    dti_dir=${outdir}/dti_maps
    mkdir -p "$dti_dir"

    tensor=${dti_dir}/tensor.nii.gz
    fa=${dti_dir}/fa.nii.gz
    md=${dti_dir}/md.nii.gz
    rd=${dti_dir}/rd.nii.gz
    ad=${dti_dir}/ad.nii.gz

    dwi2tensor -fslgrad $rotated_bvecs $working_bval $dwi_dem $tensor
    tensor2metric -fa $fa -adc $md -rd $rd -ad $ad $tensor

done
# --------------------------------------------------------------------------------
echo 'Finish preprocessing for all subjects!, Next, co-registration '
# --------------------------------------------------------------------------------

# -----------------------------------------------------------------
echo 'STEP 7: Unbias template generation'
# -----------------------------------------------------------------

for f in ${out_base}/* 
    do
        id=$(basename "$f")

        # define variables
        dir=${out_base}/${id}
        registdir=${dir}/registration
        b0=${registdir}/${id}_mean_bzero.nii.gz
        dtimaps_dir=${dir}/dti_maps
        # for the template
        template_dir=${out_base}/template
        mkdir -p ${template_dir}
        template_img=${template_dir}/my_template0.nii.gz


        # Do template with bzeros. Takes a while...
        antsMultivariateTemplateConstruction2.sh \
            -d 3 \
            -o ${template_dir}/my_ \
            -i 5 \
            ${registdir}/*_mean_bzero.nii.gz


        # -----------------------------------------------------------------
        echo 'STEP 8: Registration'
        # -----------------------------------------------------------------

        echo "Registering $id to $template_img"
        
        # first register b0 to template
        antsRegistrationSyN.sh \
            -d 3 \
            -f "$template_img" \
            -m "$b0" \
            -t br \
            -o ${registdir}/${id}_


        # now apply the transforms to the dwi maps
        for i in ${dtimaps_dir}/*
                do
                maps=$(basename "$i" | awk -F'.' '{print $1}')

                antsApplyTransforms \
                    -v 1 -d 3 \
                    -i $i \
                    -o ${registdir}/${maps}_regist.nii.gz \
                    -r $template_img \
                    -t ${registdir}/${id}_1Warp.nii.gz \
                    -t ${registdir}/${id}_0GenericAffine.mat \
                    -n Linear \
                    --float
            done    
done
    

# --------------------------------------------------------------
echo "Youre all done! :)"
# -------------------------------------------------------------- 


