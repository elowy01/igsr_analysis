#!/usr/bin/env nextflow

/* 
 * VCF benchmarking vs a truth callset
 * This workflow relies on Nextflow (see https://www.nextflow.io/tags/workflow.html)
 *
 * @author
 * Ernesto Lowy <ernesto.lowy@gmail.com>
 *
 */

// params defaults
params.help = false
params.calc_gtps = false
params.queue = 'production-rh74'

//print usage
if (params.help) {
    log.info ''
    log.info 'Pipeline to benchmark a VCF using a true VCF'
    log.info '--------------------------------------------'
    log.info ''
    log.info 'Usage: '
    log.info '    nextflow vcf_eval.nf --vcf VCF --true VCF --chros chr20 --vt snps'
    log.info ''
    log.info 'Options:'
    log.info '	--help	Show this message and exit.'
    log.info '	--vcf VCF    Path to the VCF file that will be assessed.'
    log.info '  --true VCF   Path to the high-confidence VCF that will be used as the TRUE call set.'
    log.info '  --vt  VARIANT_TYPE   Type of variant to benchmark. Possible values are 'snps'/'indels'.'
    log.info '  --chros CHROSTR	  Chromosomes that will be analyzed: chr20 or chr1,chr2.'
    log.info '  --high_conf_regions BED  BED file with high-confidence regions.'
    log.info '  --calc_gtps BOOL  If true, then calculte the genotype concordance between params.vcf'
    log.info '                    and params.true. If true, the compared VCFs should contain genotype'
    log.info '                    information.' 
    log.info ''
    exit 1
}

params.non_valid_regions = false

process excludeNonVariants {
        /*
        This process will select the variants sites on the desired chromosomes.
        Additionally, only the biallelic variants with the 'PASS' label in the filter column are considered

        Returns
        -------
        Path to a VCF file containing just the filtered sites
        */

        memory '500 MB'
        executor 'lsf'
        queue "${params.queue}"
        cpus 1

        output:
        file 'out.sites.vcf.gz' into out_sites_vcf
        when:
        !params.non_valid_regions

        """
        bcftools view -m2 -M2 -c1 ${params.vcf} -f.,PASS -r ${params.chros} -o out.sites.vcf.gz -Oz
        tabix out.sites.vcf.gz
        """
}

process excludeNonValid {
        /*
        This process will exclude the regions defined in a .BED file file from out_sites_vcf
        */

        memory '500 MB'
        executor 'lsf'
        queue "${params.queue}"
        cpus 1

        output:
        file 'out.sites.nonvalid.vcf.gz' into out_sites_nonvalid_vcf
        when:
        params.non_valid_regions

        """
        bcftools view -T ^${params.non_valid_regions} -m2 -M2 -c1 ${params.vcf} -f.,PASS -r ${params.chros} -o out.sites.nonvalid.vcf.gz -Oz
        tabix out.sites.nonvalid.vcf.gz
        """
}

process selectVariants {
	/*
	Process to select the variants from out_sites_nonvalid_vcf
	*/

	memory '500 MB'
        executor 'lsf'
        queue "${params.queue}"
        cpus 1

	input:
	file out_sites_vcf1 from out_sites_vcf.mix(out_sites_nonvalid_vcf)

	output:
	file "out.sites.${params.vt}.vcf.gz" into out_sites_vt
	
	"""
	bcftools view -v ${params.vt} ${out_sites_vcf1} -o out.sites.${params.vt}.vcf.gz -O z
	"""
}

process intersecionCallSets {
	/*
	Process to find the intersection between out_sites_vt and the TRUE call set
	*/

	memory '500 MB'
        executor 'lsf'
        queue "${params.queue}"
        cpus 1

	input:
	file out_sites_vt

	output:
	file 'dir/' into out_intersect

	"""
	tabix ${out_sites_vt}
	bcftools isec -c ${params.vt} -p 'dir/' ${out_sites_vt} ${params.true}
	"""
}

process compressIntersected {
	/*
	Process to compress the files generated by bcftools isec
	and to run BCFTools stats on these files
	*/
	publishDir 'results_'+params.chros, mode: 'copy', overwrite: true

	memory '500 MB'
        executor 'lsf'
        queue "${params.queue}"
        cpus 1

	input:
	file out_intersect

	output:
	file 'FP.vcf.gz' into fp_vcf
	file 'FN.vcf.gz' into fn_vcf
	file 'TP_target.vcf.gz' into tp_target_vcf
	file 'TP_true.vcf.gz' into tp_true_vcf
	file 'FP.stats' into fp_stats
	file 'FN.stats' into fn_stats
	file 'TP.stats' into tp_stats

	"""
	bgzip -c ${out_intersect}/0000.vcf > FP.vcf.gz
	bcftools stats ${out_intersect}/0000.vcf > FP.stats 
	bgzip -c ${out_intersect}/0001.vcf > FN.vcf.gz
	bcftools stats ${out_intersect}/0001.vcf > FN.stats
	bgzip -c ${out_intersect}/0002.vcf > TP_target.vcf.gz
	bcftools stats ${out_intersect}/0002.vcf > TP.stats
	bgzip -c ${out_intersect}/0003.vcf > TP_true.vcf.gz
	"""
}

process selectInHighConf {
	/*
	Process to select the variants in the intersected call sets
	that are in the regions defined in $params.high_conf_regions.

	This process will also convert tp_target_highconf_vcf and tp_true_highconf_vcf into .tsv files.
	This step is necessary for calculating the genotype concordance in the next process
	*/
	publishDir 'results_'+params.chros, mode: 'copy', overwrite: true
	
	memory '500 MB'
        executor 'lsf'
        queue "${params.queue}"
        cpus 1

	input:
	file fp_vcf
	file fn_vcf
	file tp_target_vcf
	file tp_true_vcf

	output:
	file 'FP.highconf.vcf.gz' into fp_highconf_vcf
	file 'FN.highconf.vcf.gz' into fn_highconf_vcf
	file 'TP_target.highconf.vcf.gz' into tp_target_highconf_vcf
	file 'TP_true.highconf.vcf.gz' into tp_true_highconf_vcf
	file 'TP_target.highconf.vcf.gz.tbi' into tp_target_highconf_vcf_tbi
	file 'TP_true.highconf.vcf.gz.tbi' into tp_true_highconf_vcf_tbi
	file 'FP.highconf.stats' into fp_highconf_stats
	file 'FN.highconf.stats' into fn_highconf_stats
	file 'TP.highconf.stats' into tp_highconf_stats
	file 'target.tsv' into target_tsv
	file 'true.tsv' into true_tsv

	"""
	tabix ${fp_vcf}
	tabix ${fn_vcf}
	tabix ${tp_target_vcf}
	tabix ${tp_true_vcf}
	bcftools view -R ${params.high_conf_regions} ${fp_vcf} -o FP.highconf.vcf.gz -Oz
	bcftools stats FP.highconf.vcf.gz > FP.highconf.stats
	bcftools view -R ${params.high_conf_regions} ${fn_vcf} -o FN.highconf.vcf.gz -Oz
	bcftools stats FN.highconf.vcf.gz > FN.highconf.stats
	bcftools view -R ${params.high_conf_regions} ${tp_target_vcf} -o TP_target.highconf.vcf.gz -Oz
	bcftools stats TP_target.highconf.vcf.gz > TP.highconf.stats
	bcftools view -R ${params.high_conf_regions} ${tp_true_vcf} -o TP_true.highconf.vcf.gz -Oz
	tabix TP_target.highconf.vcf.gz
	tabix TP_true.highconf.vcf.gz
	bcftools query -f \'[%POS\\t%REF\\t%ALT\\t%GT\\n]\' TP_true.highconf.vcf.gz > true.tsv
	bcftools query -f \'[%POS\\t%REF\\t%ALT\\t%GT\\n]\' TP_target.highconf.vcf.gz > target.tsv
	"""
}

// activate this process only if params.vcf has genotype information
if (params.calc_gtps==true) {

   process calculateGTconcordance {
   	   /*
	   Process to calculate the genotype concordance between the files
	   */
	   publishDir 'results_'+params.chros, mode: 'copy', overwrite: true

	   memory '500 MB'
           executor 'lsf'
           queue "${params.queue}"
           cpus 1

	   input:
	   file target_tsv
	   file true_tsv

	   output:
	   file 'GT_concordance.txt' into gt_conc

	   """
	   calc_gtconcordance.py ${target_tsv} ${true_tsv} > GT_concordance.txt
	   """
   }
}