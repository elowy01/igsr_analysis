/* 
 * Workflow to filter a VCF
 * This workflow relies on Nextflow (see https://www.nextflow.io/tags/workflow.html)
 *
 * @author
 * Ernesto Lowy <ernesto.lowy@gmail.com>
 *
 */

// params defaults
params.help = false


//print usage
if (params.help) {
    log.info ''
    log.info 'Pipeline to filter a VCF file using a Logistic Regression binary classifier'
    log.info '---------------------------------------------------------------------------'
    log.info ''
    log.info 'Usage: '
    log.info '    nextflow filterVCF.nf --vcf VCF --true VCF --vt snps --annotations ANNOATION_STRING --cutoff 0.95'
    log.info ''
    log.info 'Options:'
    log.info '	--help	Show this message and exit.'
    log.info '	--vcf VCF    Path to the VCF file that will be filtered.'
    log.info '  --true VCF  Path to the VCF file containing the gold-standard sites.'
    log.info '  --vt  VARIANT_TYPE   Type of variant to filter. Poss1ible values are 'snps'/'indels'.'
    log.info '  --annotations ANNOTATION_STRING	String containing the annotations to filter, for example:'
    log.info '	%CHROM\t%POS\t%INFO/DP\t%INFO/RPB\t%INFO/MQB\t%INFO/BQB\t%INFO/MQSB\t%INFO/SGB\t%INFO/MQ0F\t%INFO/ICB\t%INFO/HOB\t%INFO/MQ\n.' 
    log.info '  --cutoff FLOAT cutoff value used in the filtering.'
    log.info ''
    exit 1
}


chrList=['chr20']

chrChannel=Channel.from( chrList )


//Training the classifier. For all sites (across all the chros)

process excludeNonVariants {
	/*
	This process will select the variants on the unfiltered vcf (all chros) for
	the particular type defined by 'params.vt'

	Returns
	-------
	Path to a site-VCF file containing just the variants on a particular chromosome
	*/

	memory '500 MB'
        executor 'local'
        queue "${params.queue}"
        cpus 1

	output:
	file "out.sites.${params.vt}.vcf.gz" into out_sites_vts

	"""
	${params.bcftools_folder}/bcftools view -v ${params.vt} -G -c1 ${params.vcf} -o out.sites.${params.vt}.vcf.gz -Oz
	${params.tabix} out.sites.${params.vt}.vcf.gz
	"""
}

process intersecionCallSets {
	/*
	Process to find the intersection between out_sites_vts and the Gold standard call set
	*/

	memory '500 MB'
        executor 'local'
        queue "${params.queue}"
        cpus 1

	input:
	file out_sites_vts

	output:
	file 'dir/' into out_intersect

	"""
	tabix ${out_sites_vts}
	${params.bcftools_folder}/bcftools isec -c ${params.vt}  -p 'dir/' ${out_sites_vts} ${params.true}
	"""
}

process compressIntersected {
        /*
        Process to compress the files generated by bcftools isec
        */
        memory '500 MB'
        executor 'local'
        queue "${params.queue}"
        cpus 1

        input:
        file out_intersect

        output:
        file 'FP.vcf.gz' into fp_vcf
        file 'FN.vcf.gz' into fn_vcf
        file 'TP.vcf.gz' into tp_vcf

        """
        ${params.bgzip} -c ${out_intersect}/0000.vcf > FP.vcf.gz
        ${params.bgzip} -c ${out_intersect}/0001.vcf > FN.vcf.gz
        ${params.bgzip} -c ${out_intersect}/0002.vcf > TP.vcf.gz
        """
}

process get_variant_annotations {
	/*
	Process to get the variant annotations for training files 
	and for VCF file to annotate (for a single chromosome in this case)
	*/

	memory '2 GB'
        executor 'local'
        queue "${params.queue}"
        cpus 1

	input:
	file tp_vcf
	file fp_vcf
	val chr from chrChannel

	output:
	file 'TP_annotations.tsv' into tp_annotations
	file 'FP_annotations.tsv' into fp_annotations
	file 'unfilt_annotations.snps.tsv' into unfilt_annotations
	val chr into chr

	"""
	${params.bcftools_folder}/bcftools query -H -f '${params.annotations}' ${tp_vcf} > TP_annotations.tsv
	${params.bcftools_folder}/bcftools query -H -f '${params.annotations}' ${fp_vcf} > FP_annotations.tsv
	${params.bcftools_folder}/bcftools query -H -r ${chr} -f '${params.annotations}' ${params.vcf} > unfilt_annotations.snps.tsv
	"""
}

process train_model {
	/*
	Process that takes TP_annotations.tsv and FP_annotations.tsv created above and will train the Logistic
	Regression binary classifier
	*/

	memory '2 GB'
        executor 'local'
        queue "${params.queue}"
        cpus 1

	input:
	file tp_annotations
	file fp_annotations

	output:
	file 'fitted_logreg_snps.sav' into trained_model

	"""
	#!/usr/bin/env python

	from VCF.VCFfilter.MLclassifier import MLclassifier

	ML_obj=MLclassifier(bcftools_folder = '${params.bcftools_folder}')

	outfile=ML_obj.train(outprefix="fitted_logreg_snps",
			tp_annotations='${tp_annotations}',
			fp_annotations='${fp_annotations}')
	"""
}

process apply_model {
	/*
	Process to read-in the serialized ML model created in the 'train_model' analysis
	and to apply this model on the unfiltered VCF
	*/

	memory '2 GB'
        executor 'local'
        queue "${params.queue}"
        cpus 1

	input:
	file trained_model
	file unfilt_annotations

	output:
	file 'predictions.tsv' into predictions

	"""
	#!/usr/bin/env python

	from VCF.VCFfilter.MLclassifier import MLclassifier

	ML_obj=MLclassifier(bcftools_folder = '${params.bcftools_folder}',
		fitted_model = '${trained_model}')

	ML_obj.predict(outprefix="predictions", annotation_f='${unfilt_annotations}', cutoff=${params.cutoff})
	"""
}

process compress_predictions {
	/*
	Process to compress and index the 'predictions.tsv' file generated by process 'apply_model'
	*/

	memory '500 MB'
        executor 'local'
        queue "${params.queue}"
        cpus 1

	input:
	file predictions

	output:
	file 'predictions.tsv.gz' into predictions_table
	file 'predictions.tsv.gz.tbi' into predictions_table_tabix

	"""
	${params.bgzip} -c ${predictions} > 'predictions.tsv.gz'
	${params.tabix} -f -s1 -b3 -e3 'predictions.tsv.gz'
	"""
}

process get_header {
	/*
	Process to get the header of the unfiltered VCF
	*/

	memory '500 MB'
        executor 'local'
        queue "${params.queue}"
        cpus 1

	output:
	file 'header.txt' into header

	"""
	${params.bcftools_folder}/bcftools view -h ${params.vcf} > header.txt
	"""
}

process modify_header {
	/*
	Process to modify the header of the unfiltered VCF
	*/

	memory '500 MB'
        executor 'local'
        queue "${params.queue}"
        cpus 1

	input:
	file header

	output:
	file 'newheader.txt' into newheader

	"""
	#!/usr/bin/env python

	from VCF.VcfUtils import VcfUtils

	vcf_object=VcfUtils(vcf='${params.vcf}')

	vcf_object.add_to_header(header_f='${header}', outfilename='newheader1.txt',
                          	 line_ann='##FILTER=<ID=MLFILT,Description="Binary classifier filter">')
	vcf_object.add_to_header(header_f='newheader1.txt', outfilename='newheader.txt',
                                 line_ann='##INFO=<ID=prob_TP,Number=1,Type=Float,Description="Probability of being a True positive">')

	"""
}

process splitVCF {
	/*
	This process will filter the unfiltered VCF into a single chromosome
	*/

	memory '500 MB'
        executor 'local'
        queue "${params.queue}"
        cpus 1

	input:
	val chr

	output:
	val chr into chr_1
	file "unfilt.${chr}.${params.vt}.vcf.gz" into unfilt_vcf_chr
	
	"""
	${params.bcftools_folder}/bcftools view -r ${chr} -v ${params.vt} ${params.vcf} -o unfilt.${chr}.${params.vt}.vcf.gz -Oz
	"""
}

process replace_header {
	/*
	Process to replace header in the unfiltered VCF
	*/

	memory '500 MB'
        executor 'local'
        queue "${params.queue}"
        cpus 1

	input:
	file newheader
	file unfilt_vcf_chr

	output:
	file 'unfilt_reheaded.vcf.gz' into unfilt_vcf_chr_reheaded

	"""
	${params.bcftools_folder}/bcftools reheader -h ${newheader} -o 'unfilt_reheaded.vcf.gz' ${unfilt_vcf_chr}
	"""
}

process reannotate_vcf {
	/*
	Process to reannotate the unfiltered VCF with the information generated after applying the classifier
	*/

	memory '500 MB'
        executor 'local'
        queue "${params.queue}"
        cpus 1


	publishDir "results_${chr_1}", saveAs:{ filename -> "$filename" }

	input:
	file unfilt_vcf_chr_reheaded
	file predictions_table
	file predictions_table_tabix
	val chr_1

	output:
	file 'filt.vcf.gz' into filt_vcf

	"""
	${params.bcftools_folder}/bcftools annotate -a ${predictions_table} ${unfilt_vcf_chr_reheaded} -c CHROM,FILTER,POS,prob_TP -o filt.vcf.gz -Oz
	"""
}
