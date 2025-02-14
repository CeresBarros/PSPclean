globalVariables(c(
  "nfi_plot", ".", "meas_plot_size", "site_age", "utm_n", "utm_e", "utm_zone", "tree_num",
  "lgtree_genus", "lgtree_species", "lgtree_status", "OrigPlotID1", "MeasureYear", "dbh",
  "MeasureID", "TreeNumber", "Genus",":=", "year", "Species", "DBH", "Height", "Zone",
  "Easting", "Northing", "Elevation", "PlotSize", "baseYear", "baseSA", "elevation", "height",
  "meas_num", "damage_agent"
))

#' standardize and treat the NFI PSP data
#'
#' @param lgptreeRaw the tree measurement data
#' @param lgpHeaderRaw the plot header data
#' @param approxLocation the location data
#' @param treeDamage the tree damage data
#' @param codesToExclude damage agents to exclude from measurements
#' @param excludeAllObs if removing observations of individual trees due to damage codes,
#' remove all prior and future observations if \code{TRUE}.
#'
#' @return a list of plot and tree data.tables
#'
#' @export
#' @importFrom data.table copy setkey set
dataPurification_NFIPSP <- function(lgptreeRaw,lgpHeaderRaw, approxLocation, treeDamage,
                                    codesToExclude = "IB", excludeAllObs = TRUE) {

  lgptreeRaw <- lgptreeRaw[orig_plot_area == "Y",]
  # start from tree data to obtain plot infor
  lgptreeRaw[, year := as.numeric(substr(lgptreeRaw$meas_date, 1, 4))]
  lgpHeaderRaw[, year := as.numeric(substr(lgpHeaderRaw$meas_date, 1, 4))]
  lgpHeader <- lgpHeaderRaw[nfi_plot %in% unique(lgptreeRaw$nfi_plot), ][, .(nfi_plot, year, meas_plot_size, site_age)]
  approxLocation <- approxLocation[, .(nfi_plot, utm_n, utm_e, utm_zone, elevation)]
  approxLocation <- unique(approxLocation, by = "nfi_plot")
  lgpHeader <- setkey(lgpHeader, nfi_plot)[setkey(approxLocation, nfi_plot), nomatch = 0]
  # remove the plots without SA and location infor
  lgpHeader <- lgpHeader[!is.na(site_age), ][!is.na(utm_n), ][!is.na(utm_e), ]
  treeData <- lgptreeRaw[, .(nfi_plot, year, meas_num, tree_num, lgtree_genus, lgtree_species,
                             lgtree_status, dbh, height)][nfi_plot %in% unique(lgpHeader$nfi_plot), ]
  #DS = dead standing, M = Missing Data
  treeData <- treeData[lgtree_status != "DS" & lgtree_status != "M", ][, lgtree_status := NULL]

  #remove bad plots

  if (!is.null(codesToExclude)) {
    badTrees <- treeDamage[damage_agent %in% codesToExclude, .(nfi_plot, meas_num, tree_num)]
    message(paste("removing", nrow(badTrees), "trees in NFI due to damage agents"))
    if (excludeAllObs) {
      treeData <- treeData[!badTrees, on = c("nfi_plot", "tree_num")]
    } else {
      treeData <- treeData[!badTrees, on = c("nfi_plot", "meas_num", "tree_num")]
    }
  }
  #meas_num is needed to match damage, but not afterward
  treeData[,meas_num := NULL]

  setnames(treeData, c("nfi_plot", "year", "tree_num","lgtree_genus", "lgtree_species", "dbh", "height"),
           c("OrigPlotID1", "MeasureYear", "TreeNumber", "Genus", "Species", "DBH", "Height"))

  # names(lgpHeader) <- c("OrigPlotID1", "baseYear", "PlotSize", "baseSA", "Northing", "Easting", "Zone", "Elevation")
  setnames(lgpHeader, old = c("nfi_plot", "year", "meas_plot_size", "site_age", "utm_n", "utm_e", "utm_zone", "elevation"),
           new = c("OrigPlotID1", "baseYear", "PlotSize", "baseSA", "Northing", "Easting", "Zone", "Elevation"))

  lgpHeader <- unique(lgpHeader, by = "OrigPlotID1")
  newheader <- unique(treeData[, .(OrigPlotID1, MeasureYear)], by = c("OrigPlotID1", "MeasureYear"))
  newheader[, MeasureID := paste("NFIPSP_", row.names(newheader), sep = "")]

  treeData <- setkey(treeData, OrigPlotID1)
  treeData <- treeData[newheader, on = c("OrigPlotID1", "MeasureYear")]
  lgpHeader <- setkey(lgpHeader, OrigPlotID1)[setkey(newheader, OrigPlotID1), nomatch = 0]
  #above line changed as now there are repeat measures in NFI, so join must be on MeasureID as well as OrigPlotID1
  lgpHeader <- setkey(lgpHeader, OrigPlotID1)
  lgpHeader <- lgpHeader[newheader, on = c("OrigPlotID1", "MeasureID")]

  treeData <- treeData[, .(MeasureID, OrigPlotID1, MeasureYear,
                           TreeNumber, Genus, Species, DBH, Height)]
  lgpHeader <- lgpHeader[, .(MeasureID, OrigPlotID1, MeasureYear, Longitude = NA, Latitude = NA, Zone,
                             Easting, Northing, Elevation, PlotSize, baseYear, baseSA)]

  treeData <- standardizeSpeciesNames(treeData, forestInventorySource = "NFIPSP") #Need to add to pemisc

  treeData[, Species := paste0(Genus, "_", Species)]
  treeData[, Genus := NULL] #This column is not in any of the other PSP datasets

  treeData$OrigPlotID1 <- paste0("NFI", treeData$OrigPlotID1)
  lgpHeader$OrigPlotID1 <- paste0("NFI", lgpHeader$OrigPlotID1)

  treeData[Height <= 0, Height := NA]
  treeData <- treeData[!is.na(DBH) & DBH > 0]

  return(list(
    "plotHeaderData" = lgpHeader,
    "treeData" = treeData))
}

#' source the NFI PSP data
#' @param dPath passed to prepInputs destinationPath
#'
#' @return a list of NFI PSP data.tables
#'
#' @export
#' @importFrom reproducible prepInputs
prepInputsNFIPSP <- function(dPath) {

  pspNFILocationRaw <- prepInputs(targetFile = file.path(dPath, "all_gp_site_info.csv"),
                                  url = "https://drive.google.com/file/d/1S-4itShMXtwzGxjKPgsznpdTD2ydE9qn/view?usp=sharing",
                                  destinationPath = dPath,
                                  overwrite = TRUE,
                                  fun = 'fread')

  pspNFIHeaderRaw <- prepInputs(targetFile = file.path(dPath, "all_gp_ltp_header.csv"),
                                url = "https://drive.google.com/file/d/1i4y1Tfi-kpa5nHnpMbUDomFJOja5uD2g/view?usp=sharing",
                                destinationPath = dPath,
                                fun = 'fread',
                                overwrite = TRUE)

  pspNFITreeRaw <- prepInputs(targetFile = file.path(dPath, "all_gp_ltp_tree.csv"),
                              url = "https://drive.google.com/file/d/1i4y1Tfi-kpa5nHnpMbUDomFJOja5uD2g/view?usp=sharing",
                              destinationPath = dPath,
                              fun = 'fread',
                              overwrite = TRUE)

  pspNFITreeDamage <- prepInputs(targetFile = file.path(dPath, "all_gp_ltp_tree_damage.csv"),
                                 url = "https://drive.google.com/file/d/1i4y1Tfi-kpa5nHnpMbUDomFJOja5uD2g/view?usp=sharing",
                                 destinationPath = dPath,
                                 fun = "fread",
                                 overwrite = TRUE)

  return(list(
    "pspLocation" = pspNFILocationRaw,
    "pspHeader" = pspNFIHeaderRaw,
    "pspTreeMeasure" = pspNFITreeRaw,
    "pspTreeDamage" = pspNFITreeDamage
  ))
}
