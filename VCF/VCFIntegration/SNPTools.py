'''
Created on 21 Jul 2017

@author: ernesto
'''
import os
import subprocess

class SNPTools(object):
    """
    Class to operate on a VCF file at the population level and perform
    different SNPTools analysis on it
    """

    def __init__(self, vcf, snptools_folder=None):
        """
        Constructor

        Parameters
        ----------
        vcf : str
              Path to vcf file.
        snptools_folder : str, optional
                          Path to folder containing the snptools binaries (bamodel, poprob, etc.).
        """

        if os.path.isfile(vcf) is False:
            raise Exception("File does not exist")

        self.vcf = vcf
        self.snptools_folder = snptools_folder

    def run_bamodel(self, sample, bamfiles, outdir=None, verbose=False):
        """
        Method that wraps SNPTools' bamodel on a VCF containing only Biallelic SNPs
        See https://www.hgsc.bcm.edu/software/snptools

        Parameters
        ----------
        sample: str
                Sample to analyze.
        bamfiles : str
                   File containing the BAM path/s (one per line) for sample.
        outdir : str, optional
                 Outdir for output files.
        verbose : bool, optional
                  If true, then print the command line used for running SNPTools.

        Returns
        -------
        str
                Returns a *.raw file
        """
        # parse bamfiles
        bamf = open(bamfiles, 'r')
        bams = list(set(bamf.read().splitlines()))
        # remove empty elements
        bams = list(filter(None, bams))

        program_folder = ""
        if self.snptools_folder:
            program_folder += self.snptools_folder + "/"

        outfile = ""
        if outdir is not None:
            outfile = "{0}/{1}".format(outdir, sample)
        else:
            outfile = "{0}".format(sample)

        bam_str = " ".join(list(filter(lambda x: sample in x, bams)))

        command = "{0}/bamodel {1} {2} {3}".format(program_folder,
                                                   outfile, self.vcf,
                                                   bam_str)

        if verbose == True:
            print("Command used was: %s" % command)

        try:
            subprocess.check_output(command, shell=True)
        except subprocess.CalledProcessError as exc:
            print("Something went wrong while running SNPTools bamodel\n"
                  "Command used was: %s" % command)
            raise Exception(exc.output)

        if os.path.isfile(outfile+".raw") == False:
            raise Exception("Something went wrong while running SNPTools bamodel\n"
                            "{0} could not be created".format(outfile))

        return outfile+".raw"

    def run_poprob(self, outprefix, rawlist, outdir=None, verbose=False):
        """
        Method that wraps SNPTools' poprob on a VCF containing only Biallelic SNPs
        See https://www.hgsc.bcm.edu/software/snptools

        Parameters
        ----------
        outprefix : str
                    Prefix for *.prob file.
        rawlist : str
                  File containing the paths to the *.raw files generated by
                  'run_snptools_bamodel'.
        outdir : str, optional
                 Outdir for output files.
        verbose : bool, optional
                  if true, then print the command line used for running SNPTools.

        Returns
        -------
        outfile : str
                Returns a *.prob file.
        """

        program_folder = ""
        if self.snptools_folder:
            program_folder += self.snptools_folder + "/"

        outfile = ""
        if outdir is not None:
            outfile = "{0}/{1}.prob".format(outdir, outprefix)
        else:
            outfile = "{0}.prob".format(outprefix)

        command = "{0}/poprob {1} {2} {3}".format(program_folder,
                                                  self.vcf,
                                                  rawlist,
                                                  outfile)

        if verbose == True:
            print("Command used was: %s" % command)

        try:
            subprocess.check_output(command, shell=True)
        except subprocess.CalledProcessError as exc:
            print("Something went wrong while running SNPTools poprob\n"
                  "Command used was: %s" % command)
            raise Exception(exc.output)

        if os.path.isfile(outfile) == False:
            raise Exception("Something went wrong while running SNPTools poprob\n"
                            "{0} could not be created".format(outfile))

        return outfile

    def run_prob2vcf(self, probf, outprefix, chro, outdir=None, verbose=False):
        """
        Method that wraps SNPTools' prob2vcf on a VCF containing only Biallelic SNPs
        See https://www.hgsc.bcm.edu/software/snptools

        Parameters
        ----------
        probf : str
               *.prob file generated by 'run_snptools_poprob'.
        outprefix : str
                    Prefix used for output file.
        chro : str
               Chromosome for which the vcf will be generated.
        outdir : str, optional
                 Outdir for output files.
        verbose : bool, optional
                  If true, then print the command line used for running SNPTools.

        Returns
        -------
        outfile : str
                Compressed VCF file with the population genotype likelihoods.

        """

        program_folder = ""
        if self.snptools_folder:
            program_folder += self.snptools_folder + "/"

        outfile = ""
        if outdir is not None:
            outfile = "{0}/{1}.vcf.gz".format(outdir, outprefix)
        else:
            outfile = "{0}.vcf.gz".format(outprefix)

        command = "{0}/prob2vcf {1} {2} {3}".format(program_folder,
                                                    probf,
                                                    outfile,
                                                    chro)

        if verbose == True:
            print("Command used was: %s" % command)

        try:
            subprocess.check_output(command, shell=True)
        except subprocess.CalledProcessError as exc:
            print("Something went wrong while running SNPTools prob2vcf\n"
                  "Command used was: %s" % command)
            raise Exception(exc.output)

        if os.path.isfile(outfile) == False:
            raise Exception("Something went wrong while running SNPTools prob2vcf\n"
                            "{0} could not be created".format(outfile))

        return outfile
