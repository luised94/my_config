## Prompt
For the following function:
load_reference_genome <- function(genome_dir = "REFGENS", genome_pattern = "S288C_refgenome.fna") {
    cat("Loading reference genome\n")
    directory_of_refgenomes <- file.path(Sys.getenv("HOME"), "data", genome_dir)
    if(!dir.exists(directory_of_refgenomes)) {
        stop("Directory with reference genomes doesnt exist.\n")
    }
    genome_file_path <- list.files(directory_of_refgenomes, pattern = genome_pattern, full.names = TRUE, recursive = TRUE)
    if (length(genome_file_path) > 1) {
        cat(sprintf("More than one file matched genome pattern %s", genome_pattern))
        print(genome_file_path)
        stop()
    }
    if(!file.exists(genome_file_path)) {
        stop("Reference genome doesnt exist.\n")
    }
    refGenome <- readFasta(genome_file_path)
    refGenome <- data.frame(chrom = names(as(refGenome, "DNAStringSet")), 
                    basePairSize = width(refGenome)) %>% filter(chrom != "chrM")
    cat("Head of refGenome.\n")
    print(head(refGenome))
    return(refGenome)
}

Simplify, robustify and eliminate too-good-for-the-users-own-good code. Modify the function to output the resulting dataframe to $HOME/data/REFGENS/. Use explicit control flow.
Naming Conventions 1. Functions - verb_noun_object format - domain prefix for modules - consistent plurality 2. Files - <domain>_<action>_<type>.<ext> - consistent separators - version tracking if needed

## Prompt
For the following function:

Consider the following function and variable structure:
determine_matching_control <- function(sample_row, sample_table, factors_to_match) {
    cat("Determining control row for sample row.\n")
    df <- sample_table
    comparison_row <- sample_row[factors_to_match]
    rows_with_same_factors <- apply(df[, factors_to_match], 1, function(row) {
        all(row == comparison_row)
    })
    is_input <- df$antibody == "Input"
    index <- as.numeric(unname(which(is_input & rows_with_same_factors)))
    return(index)
}

Simplify, eliminate redundancies, robustify and eliminate too-good-for-the-users-own-good code. Modify the function to output the resulting dataframe to $HOME/data/REFGENS/. Use explicit control flow.
Naming Conventions 1. Functions - verb_noun_object format - domain prefix for modules - consistent plurality 2. Files - <domain>_<action>_<type>.<ext> - consistent separators - version tracking if needed

## Prompt
For the following function:
chr_to_roman <- c(
  "1" = "I", "2" = "II", "3" = "III", "4" = "IV", "5" = "V", "6" = "VI", "7" = "VII", "8" = "VIII",
  "9" = "IX", "10" = "X", "11" = "XI", "12" = "XII", "13" = "XIII", "14" = "XIV", "15" = "XV", "16" = "XVI"
)

roman_to_chr <- setNames(names(chr_to_roman), chr_to_roman)

normalize_chr_names <- function(chr_names, target_style) {
  chr_names <- gsub("^chr", "", chr_names)
  normalized_chr_name <- switch(target_style,
    "UCSC" = paste0("chr", chr_names),
    "Roman" = sapply(chr_names, function(x) paste0("chr", ifelse(x %in% names(chr_to_roman), chr_to_roman[x], x))),
    "Numeric" = sapply(chr_names, function(x) ifelse(x %in% chr_to_roman, roman_to_chr[x], x)),
    stop("Unknown target style")
    )
    cat("Structure of normalized_chr_name\n")
    print(str(normalized_chr_name))
    return(unname(normalized_chr_name)) 
}

determine_chr_style <- function(chr_names) {
  if (all(grepl("^chr[0-9]+$", chr_names))) return("UCSC")
  if (all(grepl("^chr[IVX]+$", chr_names))) return("Roman")
  if (all(grepl("^[0-9]+$", chr_names))) return("Numeric")
  return("Unknown")
}
Take into account our functions above if applicable. Simplify, eliminate redundancies, robustify and eliminate too-good-for-the-users-own-good code. Use explicit control flow. Naming Conventions 1. Functions - verb_noun_object format - domain prefix for modules - consistent plurality 2. Files - <domain>_<action>_<type>.<ext> - consistent separators - version tracking if needed

## Prompt
For the following function:
load_feature_file_GRange <- function(chromosome_to_plot = 10, feature_file_pattern = "eaton_peaks", genomeRange_to_get) {
  cat(sprintf("Loading %s feature file.\n", feature_file_pattern))
  # Input validation
  feature_file_dir <- file.path(Sys.getenv("HOME"), "data", "feature_files")
  if(!dir.exists(feature_file_dir)) {
    stop(sprintf("Directory %s does not exist.", feature_file_dir))
  }
  feature_file_path <- list.files(feature_file_dir, pattern = feature_file_pattern, full.names = TRUE, recursive = TRUE)
  if(length(feature_file_path) != 1) {
    stop(sprintf("Error finding feature file. Found %d files: %s", length(feature_file_path), paste(feature_file_path, collapse = ", ")))
  }
  # Load feature file and determine its style
  feature_grange <- import.bed(feature_file_path)
  feature_style <- determine_chr_style(seqlevels(feature_grange))
  cat("Feature file chromosome style:", feature_style, "\n")
  # Determine genomeRange style
  genome_style <- determine_chr_style(seqlevels(genomeRange_to_get))
  cat("Genome range chromosome style:", genome_style, "\n")

  if (feature_style == genome_style) {
    # Styles match, use genomeRange_to_get as is
    cat("Styles match. Using provided genome range.\n")
    feature_grange_subset <- subsetByOverlaps(feature_grange, genomeRange_to_get)
  } else {
    # Styles don't match, adjust genomeRange_to_get
    cat("Styles don't match. Adjusting genome range to match feature file.\n")
    adjusted_genomeRange <- genomeRange_to_get
    new_seqlevels <- normalize_chr_names(seqlevels(genomeRange_to_get), feature_style)
    seqlevels(adjusted_genomeRange) <- new_seqlevels

    feature_grange_subset <- subsetByOverlaps(feature_grange, adjusted_genomeRange)

    new_seqlevels <- normalize_chr_names(seqlevels(feature_grange_subset), genome_style)
    seqlevels(feature_grange_subset) <- new_seqlevels
    cat(sprintf("Confirming Feature GRange file style: %s\n", determine_chr_style(seqlevels(feature_grange_subset))))

  }
  return(feature_grange_subset)
}
Take into account our functions above if applicable. Simplify, eliminate redundancies, robustify and eliminate too-good-for-the-users-own-good code. Use explicit control flow. Naming Conventions 1. Functions - verb_noun_object format - domain prefix for modules - consistent plurality 2. Files - <domain>_<action>_<type>.<ext> - consistent separators - version tracking if needed

## Prompt
For the following function:

#Create GRanges object to read in a particular chromosome
create_chromosome_GRange <- function(refGenome) {
    cat("Creating chromosome GRange for loading feature, samples, etc\n")
    genomeRange_to_get <- GRanges(seqnames = refGenome$chrom,
                                  ranges = IRanges(start = 1, 
                                                   end = refGenome$basePairSize),
                                  strand = "*")
    cat("Head of Genome Range for loading other files.\n")
    print(head(genomeRange_to_get))
    return(genomeRange_to_get)
}
Take into account our functions above if applicable. Simplify, eliminate redundancies, robustify and eliminate too-good-for-the-users-own-good code. Use explicit control flow. Naming Conventions 1. Functions - verb_noun_object format - domain prefix for modules - consistent plurality 2. Files - <domain>_<action>_<type>.<ext> - consistent separators - version tracking if needed


## Prompt
For the following function:
unique_labeling <- function(table, categories_for_label) {
    # Input validation
    if (!is.data.frame(table)) {
        stop("Input 'table' must be a data frame")
    }
    if (!is.character(categories_for_label) || length(categories_for_label) == 0) {
        stop("Input 'categories_for_label' must be a non-empty character vector")
    }
    # Ensure antibody category is always included
    if (!"antibody" %in% categories_for_label) {
    categories_for_label <- c("antibody", categories_for_label)
    }
    print(paste("Categories for label:", paste(categories_for_label, collapse = ", ")))
    # Check if all categories exist in the table
    missing_categories <- setdiff(categories_for_label, colnames(table))
    if (length(missing_categories) > 0) {
        stop(paste("The following categories are missing from the table:", 
        paste(missing_categories, collapse = ", ")))
    }
    # Identify unique values for each category
    unique_values <- lapply(table[categories_for_label], unique)
    print("Unique values for each category:")
    print(unique_values)
    # Function to construct label for a single sample
    construct_label <- function(sample) {
    differing_categories <- sapply(categories_for_label, function(cat) {
        if (length(unique_values[[cat]]) > 1 || cat == "antibody") {
            return(sample[cat])
            #return(paste(cat, sample[cat], sep = ": "))
        } else {
            return(NULL)
        }
    })
        differing_categories <- differing_categories[!sapply(differing_categories, is.null)]
        return(paste(differing_categories, collapse = "_"))
    }
    # Apply the construct_label function to each sample (row)
    labels <- apply(table, 1, construct_label)
    print("Constructed labels:")
    print(labels)
    return(unlist(labels))
}
Take into account our functions above if applicable. Simplify, eliminate redundancies, robustify and eliminate too-good-for-the-users-own-good code. Use explicit control flow. Naming Conventions 1. Functions - verb_noun_object format - domain prefix for modules - consistent plurality 2. Files - <domain>_<action>_<type>.<ext> - consistent separators - version tracking if needed

## Prompt
For the following function:
plot_all_sample_tracks <- function(sample_table, directory_path, chromosome_to_plot = 10, genomeRange_to_get, annotation_track, highlight_gr, pattern_for_bigwig = "S288C_log2ratio") {
    main_title_of_plot <- paste("Complete View of Chrom", as.character(chromosome_to_plot), sep = "")
    categories_for_label <- c("strain_source", "rescue_allele", "mcm_tag", "antibody", "timepoint_after_release")
    date_plot_created <- stringr::str_replace_all(Sys.time(), pattern = ":| |-", replacement="")  
    factors_to_match <- get_factors_to_match(sample_table)
    cat("Factors in attributes of sample_table\n")
    print(factors_to_match)
    plot_output_dir <- file.path(directory_path, "plots")
    bigwig_dir <- file.path(directory_path, "bigwig")
    cat("Plotting all sample tracks.\n")
    gtrack <- GenomeAxisTrack(name = paste("Chr ", chromosome_to_plot, " Axis", sep = ""))
    cat("===============\n")
    column_names <- colnames(sample_table)
    is_comparison_column <- grepl("^comp_", colnames(sample_table))
    comparison_columns <- column_names[is_comparison_column]
    chromosome_as_chr_roman <- paste("chr", as.roman(chromosome_to_plot), sep = "")
    subset_gr <- genomeRange_to_get[seqnames(genomeRange_to_get) == chromosome_as_chr_roman]
    for (col in comparison_columns) {
        #Need to modify this since it depends on the names I assign to the comparisons
        if (col == "comp_timecourse1108") {
        comparison_title <- sub("comp_", "", col)
        comp_title <- paste(main_title_of_plot, "\n", comparison_title, sep = "")
        cat(sprintf("Column to plot: %s\n", col))
        cat("===============\n")
        comparison_samples <- sample_table[sample_table[[col]],]
        labels <- unique_labeling(comparison_samples, categories_for_label)
        print(labels)
        all_tracks <- list()
        all_tracks <- append(all_tracks, gtrack)
        for (sample_index in 1:nrow(comparison_samples)) {
            sample_ID_pattern <- comparison_samples$sample_ID[sample_index]
            initial_matches <- list.files(bigwig_dir, pattern = as.character(sample_ID_pattern), full.names = TRUE, recursive = TRUE)
            path_to_bigwig <- initial_matches[grepl(pattern_for_bigwig, initial_matches)]
            print(path_to_bigwig)
            if (length(path_to_bigwig) == 0){
                cat(sprintf("No bigwig found for sample_ID: %s\n", sample_ID_pattern))
                cat("Results of initial matches\n")
                print(initial_matches)
            } else if (length(path_to_bigwig) == 1){
                if (sample_index == 1) {
                    cat("===============\n")
                    cat("First sample being processed. Setting the control sample based on it.\n")
                    control_index <- determine_matching_control(sample_row = comparison_samples[sample_index, ], sample_table, factors_to_match = factors_to_match)
                    if(length(control_index) == 0) {
                        cat("No control index found\n")
                        cat(sprintf("Sample row: %s\n", comparison_samples[sample_index, ]))
                        control_ID_pattern <- sample_table$sample_ID[1]
                        control_sample_name <-sample_table$short_name[1] 
                        control_initial_matches <- list.files(bigwig_dir, pattern = as.character(control_ID_pattern), full.names = TRUE, recursive = TRUE)
                        if (pattern_for_bigwig == "_bamcomp.bw"){
                            is_input_path <- lapply(strsplit(pattern_subset_bigwig_paths, "_"), function(x) length(grep(as.character(control_ID_pattern), x))) > 1
                            control_path_to_bigwig <- pattern_subset_bigwig_paths[is_input_path]
                        } else {
                            control_path_to_bigwig <- pattern_subset_bigwig_paths
                        }
                        log2ratio_paths <- control_initial_matches[grepl(pattern_for_bigwig, control_initial_matches)]
                        is_input_path <- lapply(strsplit(log2ratio_paths, "_"), function(x) length(grep(as.character(control_ID_pattern), x))) > 1
                        control_path_to_bigwig <- log2ratio_paths[is_input_path]
                    } else {
                       #control_index <- select_control_index(control_indices = control_index, max_controls = 1)
                        control_ID_pattern <- sample_table$sample_ID[control_index]
                        control_sample_name <-sample_table$short_name[control_index] 
                        control_initial_matches <- list.files(bigwig_dir, pattern = as.character(control_ID_pattern), full.names = TRUE, recursive = TRUE)
                        pattern_subset_bigwig_paths <- control_initial_matches[grepl(pattern_for_bigwig, control_initial_matches)]
                        if (pattern_for_bigwig == "_bamcomp.bw"){
                            is_input_path <- lapply(strsplit(pattern_subset_bigwig_paths, "_"), function(x) length(grep(as.character(control_ID_pattern), x))) > 1
                            control_path_to_bigwig <- pattern_subset_bigwig_paths[is_input_path]
                        } else {
                            control_path_to_bigwig <- pattern_subset_bigwig_paths
                        }
                        log2ratio_paths <- control_initial_matches[grepl(pattern_for_bigwig, control_initial_matches)]
                        is_input_path <- lapply(strsplit(log2ratio_paths, "_"), function(x) length(grep(as.character(control_ID_pattern), x))) > 1
                        control_path_to_bigwig <- log2ratio_paths[is_input_path]
                    }
                    if(length(control_path_to_bigwig) == 0){
                        cat("Appropriate control bigwig and index one failed. Setting to second sample.\n")
                        control_ID_pattern <- sample_table$sample_ID[2]
                        control_sample_name <-sample_table$short_name[2] 
                        control_initial_matches <- list.files(bigwig_dir, pattern = as.character(control_ID_pattern), full.names = TRUE, recursive = TRUE)
                        pattern_subset_bigwig_paths <- control_initial_matches[grepl(pattern_for_bigwig, control_initial_matches)]
                        if (pattern_for_bigwig == "_bamcomp.bw"){
                            is_input_path <- lapply(strsplit(pattern_subset_bigwig_paths, "_"), function(x) length(grep(as.character(control_ID_pattern), x))) > 1
                            control_path_to_bigwig <- pattern_subset_bigwig_paths[is_input_path]
                        } else {
                            control_path_to_bigwig <- pattern_subset_bigwig_paths
                        }
                        log2ratio_paths <- control_initial_matches[grepl(pattern_for_bigwig, control_initial_matches)]
                        is_input_path <- lapply(strsplit(log2ratio_paths, "_"), function(x) length(grep(as.character(control_ID_pattern), x))) > 1
                        control_path_to_bigwig <- log2ratio_paths[is_input_path]
                    }
                    print("Name of the control bigwig path")
                    print(control_path_to_bigwig)
                    control_bigwig_to_plot <- import(con = control_path_to_bigwig, which = subset_gr)
                    control_track_to_plot <- DataTrack(control_bigwig_to_plot, type = "l", name = "Input", col = "#fd0036", chromosome = chromosome_as_chr_roman)
                    sample_short_name <- comparison_samples$short_name[sample_index]
                    bigwig_to_plot <- import(con = path_to_bigwig, which = subset_gr)
                    track_to_plot <- DataTrack(bigwig_to_plot, type = "l", name = labels[sample_index], col = "#fd0036", chromosome = chromosome_as_chr_roman)
                    print(track_to_plot)
                    all_tracks <- append(all_tracks, control_track_to_plot)
                    all_tracks <- append(all_tracks, track_to_plot)
                } else {
                    sample_short_name <- comparison_samples$short_name[sample_index]
                    bigwig_to_plot <- import(con = path_to_bigwig, which = subset_gr)
                    track_to_plot <- DataTrack(bigwig_to_plot, type = "l", name = labels[sample_index], col = "#fd0036", chromosome = chromosome_as_chr_roman)
                    all_tracks <- append(all_tracks, track_to_plot)
                }
            }
    pattern_for_bigwig_name_sans_underscore <- gsub("_|\\.bw", "", pattern_for_bigwig)
    comparison_name_sans_underscore <- gsub("_", "", col)
    sample_timeid <- basename(strsplit(path_to_bigwig, "_")[[1]])[1]
    all_tracks <- append(all_tracks, annotation_track)
    output_plot_name <- paste(plot_output_dir, "/", date_plot_created, "_", sample_timeid, "_", chromosome_as_chr_roman, "_", pattern_for_bigwig_name_sans_underscore,"_", comparison_name_sans_underscore, "_", ".svg", sep = "")
    print("Name of the plot to be generated")
    print(output_plot_name)
    cat(sprintf("End of for loop for %s ====\n", col))
    #svg(output_plot_name)
    plotTracks(all_tracks, 
                main = comp_title,
                chromosome = chromosome_as_chr_roman)
                #ylim = c(0, 100000))
    #dev.off()
    
}
    } else {
        cat(sprintf("Testing. Only plotting %s\n", col))
    }
    cat("All comparisons plotted ===============\n")
}
Take into account our functions above if applicable. Simplify, eliminate redundancies, robustify and eliminate too-good-for-the-users-own-good code. Use explicit control flow. Naming Conventions 1. Functions - verb_noun_object format - domain prefix for modules - consistent plurality 2. Files - <domain>_<action>_<type>.<ext> - consistent separators - version tracking if needed

## Prompt

Assume the following:
The metadata for comparisons is stored in $HOME/data/241007Bel/241007Bel_processed_grid.csv
and the source the file ~/lab_utils/scripts/bmc_config.R which generates a EXPERIMENT_CONFIG variable of the form:
EXPERIMENT_CONFIG <- list(
    METADATA = list(
        EXPERIMENT_ID = "241007Bel",
        EXPECTED_SAMPLES = 65,
        VERSION = "1.0.0"
    ),    
    CATEGORIES = list(
        rescue_allele = c("NONE", "WT", "4R", "PS"),
        auxin_treatment = c("NO", "YES"),
        time_after_release = c("0", "1", "2"),
        antibody = c("Input", "ProtG", "HM1108", "V5", "ALFA", "UM174")
    ),    
    INVALID_COMBINATIONS = list(
        rescue_allele_auxin_treatment = quote(rescue_allele %in% c("4R", "PS") & auxin_treatment == "NO"),
        protg_time_after_release = quote(antibody == "ProtG" & time_after_release %in% c("1", "2")),
        input_time_after_release = quote(antibody == "Input" & time_after_release %in% c("1", "2")),
        input_rescue_allele_auxin_treatment = quote(antibody == "Input" & rescue_allele %in% c("NONE", "WT") & auxin_treatment == "YES")
    ),    
    EXPERIMENTAL_CONDITIONS = list(
        is_input = quote(time_after_release == "0" & antibody == "Input"),
        is_protg = quote(rescue_allele == "WT" & time_after_release == "0" & antibody == "ProtG" & auxin_treatment == "NO"),
        is_v5 = quote(antibody == "V5"),
        is_alfa = quote(antibody == "ALFA"),
        is_1108 = quote(antibody == "HM1108" & time_after_release == "0"),
        is_174 = quote(antibody == "UM174")
    ),    
    COMPARISONS = list(
        comp_1108forNoneAndWT = quote(antibody == "HM1108" & rescue_allele %in% c("NONE", "WT")),
        comp_1108forNoneAndWT_auxin = quote(antibody == "HM1108" & auxin_treatment == "YES"),
        comp_timeAfterReleaseV5WT = quote(antibody == "V5" & rescue_allele == "WT" & auxin_treatment == "YES"),
        comp_timeAfterReleaseV5NoTag = quote(antibody == "V5" & rescue_allele == "NONE" & auxin_treatment == "YES"),
        comp_V5atTwoHours = quote(antibody == "V5" & time_after_release == "2" & auxin_treatment == "YES"),
        comp_UM174atTwoHours = quote(antibody == "UM174" & time_after_release == "2" & auxin_treatment == "YES"),
        comp_ALFAforNoRescueNoTreat = quote(antibody == "ALFA" & rescue_allele == "NONE" & auxin_treatment == "NO"),
        comp_ALFAforNoRescueWithTreat = quote(antibody == "ALFA" & rescue_allele == "NONE" & auxin_treatment == "YES"),
        comp_ALFAatTwoHoursForAllAlleles = quote(antibody == "ALFA" & time_after_release == "2" & auxin_treatment == "YES"),
        comp_UM174atZeroHoursForAllAlleles = quote(antibody == "UM174" & time_after_release == "0" & auxin_treatment == "YES"),
        comp_AuxinEffectOnUM174 = quote(antibody == "UM174" & time_after_release == "2" & rescue_allele %in% c("NONE", "WT"))
    ),    
    CONTROL_FACTORS = list(
        genotype = c("rescue_allele")
    ),
    COLUMN_ORDER = c("antibody", "rescue_allele", "auxin_treatment", "time_after_release")
)
We have a load_metadata and an analyze_comparisons function that load the csv and one that subsets the resulting dataframe using the COMPARISONS list in the EXPERIMENT_CONFIG. 

We have to integrate the assumptions into a script that generates the plots for each of the COMPARISONS in the EXPERIMENT_CONFIG variable.
Take into account our functions above if applicable. Simplify, eliminate redundancies, robustify and eliminate too-good-for-the-users-own-good code. Use explicit control flow. Naming Conventions 1. Functions - verb_noun_object format - domain prefix for modules - consistent plurality 2. Files - <domain>_<action>_<type>.<ext> - consistent separators.
