#Check this script is in the same directory as the .gmt files below, or add path accordingly (need to be downloaded first from https://www.gsea-msigdb.org/gsea/msigdb/mouse/collections.jsp)

# Define a helper to find files (looking in current dir, gsea/, R_scripts/gsea/)
find_gmt <- function(pattern) {
    dirs <- c(".", "gsea", "R_scripts/gsea")
    for (d in dirs) {
        if (dir.exists(d)) {
            f <- list.files(d, pattern = pattern, full.names = TRUE)
            if (length(f) > 0) return(f[1])
        }
    }
    return(NULL)
}

# Hallmark
f <- find_gmt("h\\.all.*\\.gmt")
if (!is.null(f)) {
    message("Loading Hallmark pathways from: ", f)
    pathways.hallmark <- gmtPathways(f)
} else {
    message("Hallmark pathways (.gmt) not found. Skipping.")
}

# Biological Processes
f <- find_gmt("c5\\.(go\\.)?bp.*\\.gmt")
if (!is.null(f)) {
    message("Loading BP pathways from: ", f)
    pathways.bio_processes <- gmtPathways(f)
}

# Molecular Functions
f <- find_gmt("c5\\.(go\\.)?mf.*\\.gmt")
if (!is.null(f)) {
    message("Loading MF pathways from: ", f)
    pathways.mol_funs <- gmtPathways(f)
}

# Cellular Components
f <- find_gmt("c5\\.(go\\.)?cc.*\\.gmt")
if (!is.null(f)) {
    message("Loading CC pathways from: ", f)
    pathways.cell_comp <- gmtPathways(f)
}

# KEGG
f <- find_gmt("c2\\.cp\\.kegg.*\\.gmt")
if (!is.null(f)) {
    message("Loading KEGG pathways from: ", f)
    pathways.kegg <- gmtPathways(f)
}
