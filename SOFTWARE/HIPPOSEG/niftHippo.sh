#!/bin/bash

# niftHippo.sh script extracted from template directory 24 July 2012 and modified as documented
# SV - 2020-Feb-20: Modified to stop it being madly verbose
# MODIFIED: Added probability map generation from 4D segmentation volumes

##########################################################################
##########################################################################
##########################################################################

REG_aladin=${NIFTYREG_PATH_HS}/reg_aladin
REG_f3d=${NIFTYREG_PATH_HS}/reg_f3d
REG_resample=${NIFTYREG_PATH_HS}/reg_resample
REG_transform=${NIFTYREG_PATH_HS}/reg_transform
#NIFTI_tool=${NIFTYREG_PATH}/nifti_tool
NIFTI_tool=nifti_tool
STEPS_SEG=${NIFTYSEG_PATH}/seg_LabFusion
STEPS_CALCTOPNCC=${NIFTYSEG_PATH}/seg_CalcTopNCC
SEG_MATHS=${NIFTYSEG_PATH}/seg_maths

##########################################################################
##########################################################################
##########################################################################
input=$1
DATABASE=$2
if [ ! -e ${input} ]
then
	echo "Error (1): The following image can't be found: ${input} ... Exit"
	exit -1
fi

name=`basename ${input} .gz`
name=`basename ${name} .nii`
name=`basename ${name} .img`
name=`basename ${name} .hdr`

GW_T1=${DATABASE}/groupwise_average.nii.gz
GW_brainmask_T1=${DATABASE}/groupwise_mask.nii.gz
GW_leftHippo=${DATABASE}/groupwise_hippo_left.nii.gz
GW_rightHippo=${DATABASE}/groupwise_hippo_right.nii.gz
TEMPLATE_FOLDER=${DATABASE}/templates
num_preselect=75
NumbLNCC=15

echo "Segmenting ${input} with $num_preselect templates in the preselection stage and $NumbLNCC for the fusion step"
# Create a temporary folder
temp_folder=temp.NiftHippo.${name}.$$
if [ -d ${temp_folder} ] ; then
	rm -rf ${temp_folder}
fi
mkdir ${temp_folder}

###################################
###################################
## Extract both regions of interest
###################################
###################################

# Initial registration
###################################
${REG_aladin} \
	-source ${input} \
	-target ${GW_T1} \
	-tmask ${GW_brainmask_T1} \
	-aff ${temp_folder}/gw_to_${name}_affine_mat.txt \
	-result ${temp_folder}/gw_to_${name}_affine_res.nii.gz\
	-ln 4 -lp 3 -maxit 10
	
${REG_transform} \
	-target ${GW_T1} \
	-invAffine \
	${temp_folder}/gw_to_${name}_affine_mat.txt \
	${temp_folder}/gw_to_${name}_affine_mat.txt
if [ ! -e ${temp_folder}/gw_to_${name}_affine_mat.txt ]
then
	echo "Error (1): [NiftHippo ERROR] Affine from groupwise to input image"
	exit
fi
${REG_f3d} \
	-target ${input} \
	-source ${GW_T1} \
	-aff ${temp_folder}/gw_to_${name}_affine_mat.txt \
	-result ${temp_folder}/gw_to_${name}_nrr_res.nii.gz \
	-cpp ${temp_folder}/gw_to_${name}_nrr_cpp.nii.gz \
	-lp 2 -voff
	
if [ ! -e ${temp_folder}/gw_to_${name}_nrr_cpp.nii.gz  ]
then
	echo "Error (1): [NiftHippo ERROR] Non-rigid from groupwise to input image"
	exit
fi
###################################
for side in l r
do
	if [ ! -e ${name}_${side}_NiftHippo.nii.gz ]
	then
		# Define the ROI
		sourceImage=${GW_leftHippo}
		if [ "${side}" == "r" ]; then sourceImage=${GW_rightHippo};fi
	
	
		${REG_resample} \
			-target ${input} \
			-source ${sourceImage} \
			-cpp ${temp_folder}/gw_to_${name}_nrr_cpp.nii.gz \
			-TRI \
			-result ${temp_folder}/${side}_hippo_roi_${name}.nii.gz
		if [ ! -e ${temp_folder}/${side}_hippo_roi_${name}.nii.gz ]
		then
			echo "Error (1): [NiftHippo ERROR] ROI extraction"
			exit
		fi

		cp ${temp_folder}/${side}_hippo_roi_${name}.nii.gz ${temp_folder}/${side}_hippo_binseg_${name}.nii.gz

		fslmaths \
			${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
			-s 3 -bin \
			${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
			-odt char
		###########################
		# Extract the ROI
		ROI=(`fslstats ${temp_folder}/${side}_hippo_roi_${name}.nii.gz -w`)
		fslroi \
			${temp_folder}/${side}_hippo_binseg_${name}.nii.gz \
		        ${temp_folder}/${side}_hippo_binseg_${name}.nii.gz \
		        ${ROI[@]}

		fslroi \
			${input} \
			${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
			${ROI[@]}
		###########################
		# Change the origin - Qform
		qto_xyz=(`${NIFTI_tool} -disp_nim -infiles ${input} -field qto_xyz -quiet`)
		origin_x=`echo "${ROI[0]} ${ROI[2]} ${ROI[4]} ${qto_xyz[@]}" | awk '{print $1 * $4  + $2 * $5  + $3 * $6  + $7}'`
		origin_y=`echo "${ROI[0]} ${ROI[2]} ${ROI[4]} ${qto_xyz[@]}" | awk '{print $1 * $8  + $2 * $9  + $3 * $10 + $11}'`
		origin_z=`echo "${ROI[0]} ${ROI[2]} ${ROI[4]} ${qto_xyz[@]}" | awk '{print $1 * $12 + $2 * $13 + $3 * $14 + $15}'`
		${NIFTI_tool} \
			-infiles ${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
			-mod_nim \
			-overwrite \
			-mod_field qform_code 1 \
			-mod_field sform_code 0 \
			-mod_field qoffset_x ${origin_x} \
			-mod_field qoffset_y ${origin_y} \
			-mod_field qoffset_z ${origin_z}
		###########################
		# Change the origin - Sform if defined
		sform_code=`${NIFTI_tool} -disp_nim -infiles ${input} -field sform_code -quiet`
		if [ "${sform_code}" -gt 0 ]
		then
			sto_xyz=(`${NIFTI_tool} -disp_nim -infiles ${input} -field sto_xyz -quiet`)
			origin_x=`echo "${ROI[0]} ${ROI[2]} ${ROI[4]} ${sto_xyz[@]}" | awk '{print $1 * $4  + $2 * $5  + $3 * $6  + $7}'`
			origin_y=`echo "${ROI[0]} ${ROI[2]} ${ROI[4]} ${sto_xyz[@]}" | awk '{print $1 * $8  + $2 * $9  + $3 * $10 + $11}'`
			origin_z=`echo "${ROI[0]} ${ROI[2]} ${ROI[4]} ${sto_xyz[@]}" | awk '{print $1 * $12 + $2 * $13 + $3 * $14 + $15}'`
			sto_xyz=`echo "${sto_xyz[@]} ${origin_x} ${origin_y} ${origin_z}" | awk '{print $1 " " $2 " " $3 " " $17 " " $5 " " $6 " " $7 " " $18 " " $9 " " $10 " " $11 " " $19 " 0 0 0 1"}'`
			${NIFTI_tool} \
				-infiles ${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
				-mod_nim \
				-overwrite \
				-mod_field sform_code 1 \
				-mod_field sto_xyz "${sto_xyz}"
		fi
		###########################
	fi
done
###################################

###########################################
###########################################
## Propagate all templates to the new image
###########################################
###########################################

for side in l r
do
	if [ ! -e ${name}_${side}_NiftHippo.nii.gz ]
	then
	warpedTemplateList=""
	templateNumber=0
	###################################
    echo "Coarse registration of templates to the target image (${side})"
	for template in `ls ${TEMPLATE_FOLDER}/*_${side}.nii.gz`
	do
		###########################
		# Extract the name of the T1w corresponding image
		template_name=`basename ${template} _${side}.nii.gz`
		###########################
		# Create the deformation field
		
		${REG_f3d} \
			-target ${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
			-source ${TEMPLATE_FOLDER}/${template_name}.nii.gz \
			-aff ${temp_folder}/gw_to_${name}_affine_mat.txt \
			-result ${temp_folder}/warped_${template_name}_${side}.nii.gz \
			-ln 3 \
			-lp 1 \
			-be 0.01 \
			-voff
		
		if [ ! -e ${temp_folder}/warped_${template_name}_${side}.nii.gz ]
		then
			echo "Error (1): [NiftHippo ERROR] Template resampling to input ROI"
			exit
		fi
		###########################
		# Store the warped image name
		warpedTemplateList="${warpedTemplateList} ${temp_folder}/warped_${template_name}_${side}.nii.gz"
		templateNumber=`expr ${templateNumber} + 1`
	done
	###################################
	echo  Finding best templates
	echo ${STEPS_CALCTOPNCC} \
			-target ${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
			-templates ${templateNumber} ${warpedTemplateList} \
			-n ${num_preselect} \
			-mask ${temp_folder}/${side}_hippo_binseg_${name}.nii.gz
	best_templates=`${STEPS_CALCTOPNCC} \
			-target ${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
			-templates ${templateNumber} ${warpedTemplateList} \
			-n ${num_preselect} \
			-mask ${temp_folder}/${side}_hippo_binseg_${name}.nii.gz`
	##################################
	
	echo Best Templates: 
	echo ${best_templates}
	warpedTemplateList=""
	warpedSegmentationList=""
	
	for template in ${best_templates}
	do
		###########################
		template_name=`basename ${template} _${side}.nii.gz`
		template_name=`echo $template_name | awk -F 'rped_' {'print $2'}`
		echo Fine registration of ${template_name} to the target image
		# Extract the original T1w name
		source=${TEMPLATE_FOLDER}/${template_name}.nii.gz
		hippo=${TEMPLATE_FOLDER}/${template_name}_${side}.nii.gz
		###########################
		# Registration from template to subject
		${REG_f3d} \
			-target ${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
			-source ${source} \
			-aff ${temp_folder}/gw_to_${name}_affine_mat.txt \
			-result ${temp_folder}/${template_name}_to_${name}_${side}_nrr_res.nii.gz \
			-cpp ${temp_folder}/${template_name}_to_${name}_${side}_nrr_cpp.nii.gz \
			-sx -2.5 \
			-be 0.01 -voff
			
		if [ ! -e ${temp_folder}/${template_name}_to_${name}_${side}_nrr_cpp.nii.gz ]
		then
			echo "Error (1): [NiftHippo ERROR] Non-rigid template to input ROI"
			exit
		fi
		${REG_resample} \
			-target ${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
			-source ${hippo} \
			-cpp ${temp_folder}/${template_name}_to_${name}_${side}_nrr_cpp.nii.gz \
			-result ${temp_folder}/${template_name}_to_${name}_${side}_seg.nii.gz \
			-NN
			
		if [ ! -e ${temp_folder}/${template_name}_to_${name}_${side}_seg.nii.gz ]
		then
			echo "Error (1): [NiftHippo ERROR] Segmentation propagation from template to input ROI"
			exit
		fi
		warpedTemplateList="${warpedTemplateList} ${temp_folder}/${template_name}_to_${name}_${side}_nrr_res.nii.gz "
		warpedSegmentationList="${warpedSegmentationList} ${temp_folder}/${template_name}_to_${name}_${side}_seg.nii.gz "
	done
	#################################
	fslmerge -t ${temp_folder}/${side}_allTemplates_${name}.nii.gz ${warpedTemplateList}
	fslmerge -t ${temp_folder}/${side}_allSegmentation_${name}.nii.gz ${warpedSegmentationList}
	
	####### MODIFICATION: Generate both simple and weighted probability maps #######
	echo "############# Generating simple averaged probability map for ${side} hippocampus #############"
	# Method 1: Simple averaging approach - clean and easy to understand
	/usr/local/bin/compute_simple_probability.sh \
		${temp_folder}/${side}_allSegmentation_${name}.nii.gz \
		${temp_folder}/${side}_hippo_prob_simple_roi_${name}.nii.gz
	echo "Simple probability map (ROI) saved: ${temp_folder}/${side}_hippo_prob_simple_roi_${name}.nii.gz"
	
	# echo "############# Generating STEPS-like weighted probability map for ${side} hippocampus #############"
	# Method 2: STEPS-like weighted approach - more sophisticated similarity weighting
	# /usr/local/bin/compute_steps_probability.sh \
	#	${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
	#	${temp_folder}/${side}_allTemplates_${name}.nii.gz \
	#	${temp_folder}/${side}_allSegmentation_${name}.nii.gz \
	#	${temp_folder}/${side}_hippo_prob_weighted_roi_${name}.nii.gz \
	#	${NumbLNCC}
	# echo "Weighted probability map (ROI) saved: ${temp_folder}/${side}_hippo_prob_weighted_roi_${name}.nii.gz"
	############################################################################################
	
	rm ${temp_folder}/warped_*_${side}.nii.gz -f
	rm ${temp_folder}/*_to_${name}_${side}_seg.nii.gz -f
	rm ${temp_folder}/*_to_${name}_${side}_nrr_res.nii.gz -f

	${STEPS_SEG} \
		-in  ${temp_folder}/${side}_allSegmentation_${name}.nii.gz \
		-STEPS 2 \
                   ${NumbLNCC} \
                   ${temp_folder}/${side}_hippo_roi_${name}.nii.gz \
                   ${temp_folder}/${side}_allTemplates_${name}.nii.gz \
                -MRF_beta 0.55\
		-out ${temp_folder}/${side}_hippo_seg_roi_${name}.nii.gz \
			
	
	if [ ! -e ${temp_folder}/${side}_hippo_seg_roi_${name}.nii.gz ]
	then
		echo "Error (1): [NiftHippo ERROR] Fusion"
		exit
	fi
	
	rm ${temp_folder}/${side}_allSegmentation_${name}.nii.gz -f
	rm ${temp_folder}/${side}_allTemplates_${name}.nii.gz -f
	
	###################################
	${REG_resample} \
		-target ${input} \
		-source ${temp_folder}/${side}_hippo_seg_roi_${name}.nii.gz \
		-result ${name}_${side}_NiftHippo.nii.gz \
		-NN
		
	####### MODIFICATION: Resample both probability maps to original image space #######
	# Resample simple averaged probability map
	${REG_resample} \
		-target ${input} \
		-source ${temp_folder}/${side}_hippo_prob_simple_roi_${name}.nii.gz \
		-result ${name}_${side}_NiftHippo_prob_simple.nii.gz \
		-TRI
	echo "Final simple probability map saved: ${name}_${side}_NiftHippo_prob_simple.nii.gz"
	
	# Resample weighted probability map
	# ${REG_resample} \
	#	-target ${input} \
	#	-source ${temp_folder}/${side}_hippo_prob_weighted_roi_${name}.nii.gz \
	#	-result ${name}_${side}_NiftHippo_prob_weighted.nii.gz \
	#	-TRI
	# echo "Final weighted probability map saved: ${name}_${side}_NiftHippo_prob_weighted.nii.gz"
	####################################################################################
		
	if [ ! -e ${name}_${side}_NiftHippo.nii.gz ]
	then
		echo "[NiftHippo ERROR] final resampling in original input image"
		exit
	fi
        ${SEG_MATHS} ${name}_${side}_NiftHippo.nii.gz -lconcomp ${name}_${side}_NiftHippo.nii.gz
	##################################
	
	fi
done
###########################################
rm ${temp_folder}/*_to_${name}_*_affine_mat.txt -f
rm ${temp_folder}/*_to_${name}_*_affine_res.nii.gz -f
rm ${temp_folder}/*_to_${name}_*_nrr_res.nii.gz -f
rm ${temp_folder}/*_to_${name}_*_nrr_cpp.nii.gz -f
rm ${temp_folder}/*_to_${name}_*_seg.nii.gz -f
rm -rf ${temp_folder} -f
########################################### 