## Purpose: Create the .RData for the raw OTU phyloseq object
## Author: Marian L. Schmidt 
## Last Edit: January 31st, 2017

# Set up file
library(phyloseq)
library(dplyr)
library(tidyr)
library(picante)
source("Muskegon_functions.R")


############################################################################################################################################
############################################################################################################################################
###################################################################### LOAD IN THE DATA 
#  Load in the taxonomy and shared data
otu_tax <- "../data/mothur/stability.trim.contigs.good.unique.good.filter.unique.precluster.pick.pick.an.unique_list.0.03.cons.taxonomy"
otu_shared <- "../data/mothur/stability.trim.contigs.good.unique.good.filter.unique.precluster.pick.pick.an.unique_list.shared"
otu_physeq <- import_mothur(mothur_shared_file = otu_shared, mothur_constaxonomy_file = otu_tax)


tree_otu <- read.tree(file = "../data/fasttree/newick_tree_16s_OTU.tre")

otu_data <- merge_phyloseq(otu_physeq, tree_otu)


# Fix the taxonomy names
colnames(tax_table(otu_data)) <- c("Kingdom","Phylum","Class","Order","Family","Genus","Species")

############################################################################################################################################
############################################################################################################################################
###################################################################### ADD THE PROTEOBACTERIA TO THE PHYLA
phy <- data.frame(tax_table(otu_data))
Phylum <- as.character(phy$Phylum)
Class <- as.character(phy$Class)

for  (i in 1:length(Phylum)){ 
  if (Phylum[i] == "Proteobacteria"){
    Phylum[i] <- Class[i]
  } 
}

phy$Phylum <- Phylum # Add the new phylum level data back to phy
phy$OTU <- row.names(tax_table(otu_data)) # Make a column for OTU

t <- tax_table(as.matrix(phy))

tax_table(otu_data) <- t
################################################

# Sample Names
samp_names <- colnames(otu_table(otu_data))

# Create metadata info
df <- data.frame(matrix(NA, ncol = 1, nrow = length(samp_names)))
colnames(df) <- c("names")
df$names <- samp_names


############################################################################################################################################
############################################################################################################################################
###################################################################### LOAD IN METADATA
# Create metadata info
meta_df <- make_muskegon_metadata(df)

# Create a norep_water_name column
meta_df$norep_water_name <- paste(substr(meta_df$names,1,4),substr(meta_df$names,7,9), sep = "")

# Load in the extra metadata for the Muskegon Lake Project
musk_data <- read.csv("../data/metadata/processed_muskegon_metadata.csv", header = TRUE) # Load in the extra metada
musk_data_subset <- select(musk_data, -c(lakesite, limnion, month, year, project, season))
complete_meta_df <- left_join(meta_df, musk_data_subset, by = "norep_water_name")
row.names(complete_meta_df) <- complete_meta_df$names

complete_meta_df$water_name <- paste(substr(complete_meta_df$names,1,5),substr(complete_meta_df$names,7,9), sep = "")
complete_meta_df$norep_filter_name <- paste(substr(complete_meta_df$names,1,4),substr(complete_meta_df$names,6,9), sep = "")


############################################################################################################################################
############################################################################################################################################
###################################################################### MERGE REPLICATE SAMPLES 
# Add the metadata to our phyloseq object! 
##  Add metadata to OTUs
sample_data(otu_data) <- complete_meta_df
otu_data <- prune_taxa(taxa_sums(otu_data) > 0, otu_data)


# Merged metadata
merged_complete_meta_df<- 
  select(complete_meta_df, -c(names, replicate, nuc_acid_type, water_name)) %>% 
  distinct() %>%
  arrange(norep_filter_name)

## Add Production data from GVSU AWRI provided by the lab of Bopi Biddanda
bopi_data <- read.csv("../data/metadata/production_data.csv") %>%
  dplyr::rename(norep_filter_name = names)  %>% # rename "names" column to "norep_filter_name"
  select(-c(X, limnion, fraction, month, year, season))

## Merge two metadata files together!
df1 <- full_join(merged_complete_meta_df, bopi_data, by = "norep_filter_name") %>%
  select(-c(Depth, month)) 

# provide row.names to match sample
row.names(df1) <- df1$norep_filter_name



############################################################################################################################################
############################################################################################################################################
###################################################################### LOAD IN FLOW CYTOMETRY DATA

flow_cy <- read.csv2("../data/metadata/flow_cytometry.csv", header = TRUE) %>%
  select(-c(X, Season, Month, Year, Fraction, Site, Depth)) %>%
  filter(Lake == "Muskegon") %>%
  # Rename columns so they are more representative of the data within them
  rename(volume_uL = volume, 
         raw_counts = counts,
         HNA_counts = HNA,
         LNA_counts = LNA) %>%
  mutate(cells_per_uL = (raw_counts*dilution)/volume_uL,
         HNA_per_uL = (HNA_counts*dilution)/volume_uL,
         HNA_percent = (HNA_counts)/raw_counts*100,
         LNA_per_uL = (LNA_counts*dilution)/volume_uL,
         LNA_percent = (LNA_counts)/raw_counts*100,
         Nuc_acid_ratio = HNA_per_uL/LNA_per_uL) %>%
  select(-Lake)

# Create a new column so we can merge with other data frames
flow_cy$norep_water_name <- paste(substring(flow_cy$Sample_16S,1,4), substring(flow_cy$Sample_16S,7,9), sep = "")

# Join original metadata and flow cytometry metadata
df2 <- left_join(df1, flow_cy, by = "norep_water_name")
row.names(df2) <- row.names(df1)

# Fix the factor levels for nice plotting
df2$lakesite <- factor(df2$lakesite,  levels = c("MOT", "MDP", "MBR", "MIN"))
df2$station <- factor(df2$station,  levels = c("Channel", "Deep", "Bear", "River"))
df2$season <- factor(df2$season,  levels = c("Spring", "Summer", "Fall"))
df2$year <- factor(df2$year,  levels = c("2014", "2015"))


# merge samples for OTUs
otu_merged <- merge_samples(otu_data, group = "norep_filter_name", fun = "sum")

# Add nice sample information
sample_data(otu_merged) <- df2





############################################################################################################################################
############################################################################################################################################
###################################################################### SUBSET MUSKEGON LAKE SAMPLES 
# Subset Mukegon Lake samples out of the OTU phyloseq object
otu_merged_musk <- subset_samples(physeq = otu_merged, project == "Muskegon_Lake")
otu_merged_musk_pruned <- prune_taxa(taxa_sums(otu_merged_musk) > 0, otu_merged_musk) 

# Remove the flow cytometry data from the particle samples!
df3 <- sample_data(otu_merged_musk_pruned)


# # Subset the particle samples 
PA_df3 <- filter(df3, fraction %in% c("WholePart", "Particle"))
flow_cy_columns <- colnames(flow_cy)

##  Make all of the clow cytometry columns NA
for(i in flow_cy_columns){
  PA_df3[,i] <- NA
}

# Subset the FL samples
FL_df3 <- filter(df3, fraction %in% c("WholeFree", "Free", "Sediment"))

## Recombine the dataframe back together with flow cytometry information as NA for Particle Samples
final_meta_dataframe <- bind_rows(FL_df3, PA_df3)
row.names(final_meta_dataframe) <- final_meta_dataframe$norep_filter_name



############################################################################################################################################
############################################################################################################################################
###################################################################### ADD PHENOFLOW ALPHA DIVERSITY INFORMATION 
# Loads a data object called "phenoflow_diversity"
load("../data/PhenoFlow/otu_phenoflow/Phenoflow_diversity.RData")
phenoflow_diversity <- as.data.frame(phenoflow_diversity)

phenoflow_diversity$norep_filter_name <- row.names(phenoflow_diversity)

alpha_div <- phenoflow_diversity %>%
  select(-D0.bre, -sd.D0.bre) %>%
  dplyr::rename(D0_SD = sd.D0,
                D0_chao = D0.chao,
                D0_chao_sd = sd.D0.chao,
                D1_sd = sd.D1,
                D2_sd = sd.D2)

# Join the alpha diversity data with the rest of the metadata
final_meta_dataframe_alpha <- left_join(final_meta_dataframe, alpha_div, by = "norep_filter_name")



############################################################################################################################################
############################################################################################################################################
###################################################################### ADD DNA CONCENTRATION INFORMATION 
DNA_2014 <- read.csv("../data/metadata/2014_DNAextraction.csv", header = TRUE)
DNA14 <- DNA_2014 %>%
   mutate(rep_filter_name = paste(gsub("_", "", Sample)),
          norep_filter_name = paste(substring(rep_filter_name,1,4), substring(rep_filter_name,6,9), sep = ""),
          replicate = substring(rep_filter_name,5,5)) %>%
  slice(1:73) %>%
  # Select relevant columns
  dplyr::select(rep_filter_name, norep_filter_name, dna_concentration_ng_per_ul, replicate) %>%
  # Create one
  unite(rep_dna_conc, dna_concentration_ng_per_ul, replicate, sep = "_dnaconcrep") %>%
  # Remove the column to include
  dplyr::select(-rep_filter_name) %>%
  separate(rep_dna_conc, into = c("Concentration","Replicate"), sep = "_") %>%
  mutate(Replicate = replace(Replicate, Replicate == "dnaconcrep3", "dnaconcrep1")) %>%
  spread(Replicate, Concentration)



DNA_2015 <- read.csv("../data/metadata/2015_DNAextraction.csv", header = TRUE)
DNA15 <- DNA_2015 %>%
  ## Subset only the samples that were sequenced
  dplyr::filter(plate_Map %in% c("yes_plateC", "yes_plateD")) %>%
  # Create new columns with key information for subsetting and data manipulation
  mutate(rep_filter_name = sequencing_ID,
         norep_filter_name = paste(substring(rep_filter_name,1,4), substring(rep_filter_name,6,9), sep = ""),
         replicate = substring(rep_filter_name,5,5)) %>%
  # Select relevant columns
  dplyr::select(rep_filter_name, norep_filter_name, dna_concentration_ng_per_ul, replicate) %>%
  # Create one
  unite(rep_dna_conc, dna_concentration_ng_per_ul, replicate, sep = "_dnaconcrep") %>%
  # Remove the column to include
  dplyr::select(-rep_filter_name) %>%
  separate(rep_dna_conc, into = c("Concentration","Replicate"), sep = "_") %>%
  mutate(Replicate = replace(Replicate, Replicate == "dnaconcrep3", "dnaconcrep1")) %>%
  spread(Replicate, Concentration)

# Put the 2104 and 2015 data together into one data frame
DNAs <- union(DNA14, DNA15)

# Merge the rest of the metadata with the DNA concentration data!
final_meta_dataframe_alpha_DNA <- left_join(final_meta_dataframe_alpha, DNAs, by = "norep_filter_name")

# Rename the sample rows to match the sample names in the phyloseq object
row.names(final_meta_dataframe_alpha_DNA) <- final_meta_dataframe_alpha_DNA$norep_filter_name



############################################################################################################################################
############################################################################################################################################
###################################################################### FINALIZE THE PHYLOSEQ OBJECT
## Finally, add the big metadata frame to the sample_data of otu_merged_musk_pruned
bac_abunds <- final_meta_dataframe_alpha_DNA %>%
  select(norep_filter_name, year, limnion, lakesite, fraction, total_bac_abund, attached_bac) %>%
  mutate(temp_free_bac_abund = total_bac_abund - attached_bac, 
         attached_bac_abund = ifelse(fraction %in% c("WholeFree", "Free"), NA, attached_bac),
         free_bac_abund = ifelse(fraction %in% c("WholePart", "Particle"), NA,temp_free_bac_abund)) %>%
  select(norep_filter_name, attached_bac_abund, free_bac_abund)

bac_abunds$attached_bac_abund[is.na(bac_abunds$attached_bac_abund)] = ""
bac_abunds$free_bac_abund[is.na(bac_abunds$free_bac_abund)] = ""
bac_abunds <- unite(bac_abunds, fraction_bac_abund, attached_bac_abund:free_bac_abund, sep='')
bac_abunds$fraction_bac_abund[bac_abunds$fraction_bac_abund == ""] = NA

final_DF <- full_join(final_meta_dataframe_alpha_DNA, bac_abunds, by = "norep_filter_name")
row.names(final_DF) <- final_DF$norep_filter_name


############################################################################################################################################
############################################################################################################################################
###################################################################### FINALIZE THE PHYLOSEQ OBJECT
## Finally, add the big metadata frame to the sample_data of otu_merged_musk_pruned
sample_data(otu_merged_musk_pruned) <- final_DF

# Create a new file called "Phyloseq.RData" that has the phyloseq object
save(list="otu_merged_musk_pruned", file=paste0("../data/otu_merged_musk_pruned.RData")) 

