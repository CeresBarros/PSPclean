globalVariables(c(
  "tot_stand_age", ":=", "utm_zone", "utm_easting", "utm_northing",
  "area_pm", "stnd_org", "treatment", "SAMP_ID", "treatmenttimes",
  ".", "elev", "meas_yr", "baseYear", "baseSA", "OrigPlotID1",
  "Damage Agent Code", "OrigPlotID2", "tree_no", "Elevation", "PlotSize",
  "dam_1", "dam_2", "dam_3", "dam_4", "dam_5", ".N", "sub_plot_tree",
  "tree_cls", "MeasureYear", "MeasureID", "zone", "Easting", "Northing"
))

#' standardize and treat the BC PSP data
#'
#' @param treeDataRaw the tree measurement csv
#' @param plotHeaderDataRaw the plot header csv
#' @param damageAgentCodes vector of damage agent codes
#' @param codesToExclude damage agents to exclude from measurements
#' @param excludeAllObs if removing observations of individual trees due to damage codes,
#' remove all prior and future observations if \code{TRUE}.
#'
#' @return a list of plot and tree data.tables
#'
#' @export
#' @importFrom data.table setnames setkey copy
#'
dataPurification_BCPSP <- function(treeDataRaw, plotHeaderDataRaw, damageAgentCodes,
                                   codesToExclude = "IBM", excludeAllObs = TRUE) {

  treeDataRaw <- copy(treeDataRaw)
  plotHeaderDataRaw <- copy(plotHeaderDataRaw)

  headerData <- plotHeaderDataRaw[tot_stand_age != -99,][
    ,':='(utmtimes = length(unique(utm_zone)),
          eastingtimes = length(unique(utm_easting)),
          northingtimes = length(unique(utm_northing)),
          SAtimes = length(unique(tot_stand_age)),
          plotsizetimes = length(unique(area_pm)),
          standorigtimes = length(unique(stnd_org)),
          treatmenttimes = length(unique(treatment))),
    by = SAMP_ID]

  # select the natural originated and untreated
  headerData <- headerData[stnd_org == "N" | stnd_org == "F",]
  #this removes the repeated DBH utilization limits
  headerData[,treatmenttimes := length(unique(treatment)), by = c("SAMP_ID", "meas_yr")]
  # unique(headDataRaw$treatmenttimes) # 1 2
  headerData <- headerData[treatmenttimes == 1 & treatment == "UNTREATED",
                           .(SAMP_ID, utm_zone, utm_easting,
                             utm_northing, Elevation = elev, area_pm, tot_stand_age,
                             meas_yr)]

  headerData[, baseYear := min(meas_yr), by = SAMP_ID]
  headerData[, baseSA := as.integer(tot_stand_age-(meas_yr-baseYear))]
  # get the plots with locations
  headerData <- headerData[!is.na(utm_zone) & !is.na(utm_easting) & !is.na(utm_northing),]
  # get plots with plot size

  headerData <- headerData[!is.na(area_pm),][,':='(tot_stand_age = NULL, meas_yr = NULL)]

  setnames(headerData, old = c("SAMP_ID", "utm_zone", "utm_easting", "utm_northing", "area_pm"),
           new = c("OrigPlotID1", "Zone", "Easting","Northing", "PlotSize"))
  headerData <- unique(headerData, by = c("OrigPlotID1"))

  # for tree data
  #SAMP_ID is lower case in new BC dataset
  setnames(treeDataRaw, c("samp_id", "plot_no"), c("OrigPlotID1", "OrigPlotID2"))

  treeData <- treeDataRaw[OrigPlotID1 %in% unique(headerData$OrigPlotID1),]
  treeData <- treeData[sub_plot_tree == "N",][, OrigPlotID2 := as.numeric(OrigPlotID2)]
  # range(treeData$meas_yr) # 1926 2014
  # unique(treeData$Plotnumber) # 01 02 03

  #filtering damage codes - must remove tree from every measurement
  #there are unlikely to ever be trees with damage codes 3-5

  if (!is.null(codesToExclude)) {
    damAgents <- damageAgentCodes[`Damage Agent Code` %in% codesToExclude,]$Definition
    message(paste("removing trees marked as damaged by: "), paste(damAgents, collapse = ", "))
    bad1 <- treeData[dam_1 %in% codesToExclude, .(OrigPlotID1, OrigPlotID2, tree_no, meas_yr)]
    bad2 <- treeData[dam_2 %in% codesToExclude, .(OrigPlotID1, OrigPlotID2, tree_no, meas_yr)]
    bad3 <- treeData[dam_3 %in% codesToExclude, .(OrigPlotID1, OrigPlotID2, tree_no, meas_yr)]
    bad4 <- treeData[dam_4 %in% codesToExclude, .(OrigPlotID1, OrigPlotID2, tree_no, meas_yr)]
    bad5 <- treeData[dam_5 %in% codesToExclude, .(OrigPlotID1, OrigPlotID2, tree_no, meas_yr)]
    allBad <- rbind(bad1, bad2, bad3, bad4, bad5)

    message(paste("removing", nrow(allBad), "trees due to damage from BC PSP"))

    if (excludeAllObs) {
      allBad <- allBad[, .N, .(OrigPlotID1, OrigPlotID2, tree_no)]

      treeData <- treeData[!allBad, on = c("OrigPlotID1", "OrigPlotID2", "tree_no")]
    } else {
      treeData <- treeData[!allBad, on = c("OrigPlotID1", "OrigPlotID2", "tree_no", "meas_yr")]
    }
  }

  treeData <- treeData[tree_cls == 1 | tree_cls == 2,
                       .(OrigPlotID1, OrigPlotID2, meas_yr, tree_no, species, dbh, height)]

  # unique(treeData$ld)
  setnames(treeData, old = c("meas_yr", "tree_no", "species", "dbh", "height"),
                             new = c("MeasureYear", "TreeNumber", "Species", "DBH", "Height"))

  measureidtable <- unique(treeData[,.(OrigPlotID1, OrigPlotID2, MeasureYear)],
                          by = c("OrigPlotID1", "OrigPlotID2", "MeasureYear"))
  measureidtable[,MeasureID:= paste("BCPSP_",row.names(measureidtable), sep = "")]
  measureidtable <- measureidtable[,.(MeasureID, OrigPlotID1, OrigPlotID2, MeasureYear)]
  headerData <- setkey(measureidtable, OrigPlotID1)[setkey(headerData, OrigPlotID1), nomatch = 0]


  set(headerData, NULL,"OrigPlotID2", NULL)
  headerData <- headerData[,.(MeasureID, OrigPlotID1, MeasureYear, Longitude = NA,
                              Latitude = NA, Zone, Easting, Northing, Elevation,
                              PlotSize, baseYear, baseSA)]
  measureidtable <- setkey(measureidtable, OrigPlotID1, OrigPlotID2, MeasureYear)
  treeData <- measureidtable[setkey(treeData, OrigPlotID1, OrigPlotID2, MeasureYear), nomatch = 0]

  treeData <- standardizeSpeciesNames(treeData, forestInventorySource = "BCPSP") #Need to add to pemisc

  treeData$OrigPlotID1 <- paste0("BC", treeData$OrigPlotID1)
  headerData$OrigPlotID1 <- paste0("BC", headerData$OrigPlotID1)

  #final clean up
  treeData[Height <= 0, Height := NA]
  treeData <- treeData[!is.na(DBH) & DBH > 0]

  if (length(unique(treeData$OrigPlotID2)) == 1) {
    treeData[, OrigPlotID2 := NULL]
  }

  return(list(
    "plotHeaderData" = headerData,
    "treeData" = treeData))
}

#' source the BC PSP data
#' @param dPath passed to prepInputs destinationPath
#'
#' @return a list of BC PSP objects
#'
#' @export
#' @importFrom reproducible prepInputs
prepInputsBCPSP <- function(dPath) {

  pspBCtree <- prepInputs(targetFile = file.path(dPath, "PSPtree_BC.csv"),
                         url = "https://drive.google.com/file/d/1dEVz7OLhmZ935SWSTC1CRZI_ju4O3UnI/view?usp=sharing",
                         destinationPath = dPath,
                         fun = 'fread')

  pspBCplot <- prepInputs(targetFile = file.path(dPath, "PSPplot_BC.csv"),
                          url = "https://drive.google.com/file/d/1dEVz7OLhmZ935SWSTC1CRZI_ju4O3UnI/view?usp=sharing",
                          destinationPath = dPath,
                          fun = 'fread')


  pspBCdamageAgentCodes <- prepInputs(url = "https://drive.google.com/file/d/1pBX5txiKFul3CyZ805seQ9-WNx624Mg4/view?usp=sharing",
                                      targetFile = "BCForestry_DamageAgentCodes.csv",
                                      destinationPath = dPath,
                                      fun = 'fread')
  return(list(
    "plotHeaderDataRaw" = pspBCplot,
    "treeDataRaw" = pspBCtree,
    "pspBCdamageAgentCodes" = pspBCdamageAgentCodes
  ))

}
