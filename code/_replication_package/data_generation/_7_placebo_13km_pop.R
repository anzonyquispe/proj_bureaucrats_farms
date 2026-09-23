#------------------------------------------------------------------------------

library(raster)
library(dplyr)
library(lubridate)
library(parallel)
library(tidyverse)
library(sf)
library(data.table)
library(geosphere)
library(dplyr)
rm( list = ls())

#------------------------------------------------------------------------------



#------------------------------------------------------------------------------
# Main Path
#------------------------------------------------------------------------------

dbox_root <- "C:/Users/Anzony/Dropbox/sa_fires"
shell_root <- "/scratch/gpfs/ar8787/groupdata2/sa_fires"
root <- shell_root
int_path <- file.path( root, "proj_bureaucrats_farms/data_output/intermediate" )
save_path <- file.path( int_path, "_7_placebo_13km_pop" )
#------------------------------------------------------------------------------



#------------------------------------------------------------------------------
# Population Raster
#------------------------------------------------------------------------------


# AC Geometry
all_acs <-  read_sf( file.path( int_path, "_0_2_3_ACs_right_shapefile.shp" ) ) %>% 
  st_as_sf() %>% 
  st_set_crs( 4326 ) %>% 
  st_make_valid()



# all_acs_proj <- st_transform(all_acs, 7755)
# 
# # Calculate area in square kilometers
# all_acs_proj <- all_acs_proj %>%
#   mutate(area_km2 = as.numeric(st_area(geometry)) / 1e6 )
# 
# # Compute mean and median
# mean_area <- mean(all_acs_proj$area_km2, na.rm = TRUE)
# median_area <- median(all_acs_proj$area_km2, na.rm = TRUE)
# 
# radius_km <- sqrt( median_area / pi )
# radius_km
# radius_km <- sqrt( mean_area / pi )
# radius_km
# > radius_km <- sqrt( median_area / pi )
# > radius_km
# [1] 11.9046
# > radius_km <- sqrt( mean_area / pi )
# > radius_km
# [1] 12.44233

# # Create histogram
# ggplot(all_acs_proj, aes(x = area_km2)) +
#   geom_histogram(bins = 30, fill = "skyblue", color = "black") +
#   geom_vline(xintercept = mean_area, color = "red", linetype = "dashed", size = 1.2) +
#   geom_vline(xintercept = median_area, color = "darkgreen", linetype = "dotted", size = 1.2) +
#   labs(
#     title = "Histogram of AC Areas",
#     x = "Area (km²)",
#     y = "Count"
#   ) +
#   annotate("text",
#            x = mean_area,
#            y = Inf,
#            label = paste0("Mean = ", round(mean_area, 2), " km²"),
#            vjust = -0.5,
#            color = "red",
#            size = 4
#   ) +
#   annotate("text",
#            x = median_area,
#            y = Inf,
#            label = paste0("Median = ", round(median_area, 2), " km²"),
#            vjust = -2,
#            color = "darkgreen",
#            size = 4
#   ) +
#   theme_minimal()

# Read and process
grid <- st_read( file.path( int_path, "_1_AC_grid_selected.shp" ) ) %>% 
  st_as_sf() %>%
  st_set_crs( 4326) %>% 
  rename( unique_small_grid_id = unq_s__) %>% 
  dplyr::select( -are_tpt ) %>% 
  mutate( centroid = st_transform(st_centroid( st_transform(geometry, 7755)), 4326)) %>% 
  st_drop_geometry(geometry)



# Importing AC - Grid Information
index_list <- seq(1,14866748, 50000)
idx <- as.integer(Sys.getenv("SLURM_ARRAY_TASK_ID"))
# idx <- 1
obs0 <- index_list[ idx ]
obs1 <- min(obs0 + 50000 - 1, 14866748)
print(obs0)
print(obs1)

path1 <- file.path(int_path, "_4_merge_ac_grids.csv")
ac_grid_info <- fread( path1 )[obs0:obs1, ]
names(ac_grid_info)
sel.names <- c("unique_small_grid_id", "id", "split_id",
               "ac_uq_id", "year", "month", 
               "rollav_wind_speed_cellid_month", "rollav_wind_direction_cellid_month")

# Import grid at district level
all_df <- ac_grid_info %>% 
  dplyr::select( c(unique_small_grid_id, id, split_d, 
                   year, month, ac_uq_id,
                   rollav_wind_speed_cellid_month, 
                   rollav_wind_direction_cellid_month
  ) ) %>% 
  left_join(grid, by = c("unique_small_grid_id", "id", "split_d")) %>% 
  rename( split_id = split_d )




# Import population raster
pop_raster <- raster( 
  file.path( root, "proj_downwind/data_output/all_grid_by_district/population_raster_2020.tif" ) )%>% 
  readAll()


# Import selected features
temp <- all_df  %>%  
  dplyr::select(unique_small_grid_id, id, split_id, ac_uq_id, 
                rollav_wind_direction_cellid_month, centroid )

# Make the center the geometry of the points
temp <- temp %>% 
  st_as_sf( ) %>% 
  st_as_sf( coords = "centroid" )


# Functions to enlarge a line
st_ends_heading <- function(line)
{
  M <- sf::st_coordinates(line)
  i <- c(2, nrow(M) - 1)
  j <- c(1, -1)
  
  headings <- mapply(i, j, FUN = function(i, j) {
    Ax <- M[i-j,1]
    Ay <- M[i-j,2]
    Bx <- M[i,1]
    By <- M[i,2]
    unname(atan2(Ay-By, Ax-Bx))
  })
  
  return(headings)
}
st_extend_line <- function(line, distance, end = "BOTH")
{
  if (!(end %in% c("BOTH", "HEAD", "TAIL")) | length(end) != 1) stop("'end' must be 'BOTH', 'HEAD' or 'TAIL'")
  
  M <- sf::st_coordinates(line)[,1:2]
  keep <- !(end == c("TAIL", "HEAD"))
  
  ends <- c(1, nrow(M))[keep]
  headings <- st_ends_heading(line)[keep]
  distances <- if (length(distance) == 1) rep(distance, 2) else rev(distance[1:2])
  
  M[ends,] <- M[ends,] + distances[keep] * c(cos(headings), sin(headings))
  newline <- sf::st_linestring(M)
  
  # If input is sfc_LINESTRING and not sfg_LINESTRING
  if (is.list(line)) newline <- sf::st_sfc(newline, crs = sf::st_crs(line))
  
  return(newline)
}


attempt_split <- function(geometry, final_line) {
  buffer_sizes <- c(0, seq(10, 1000, by = 10))  # Start with 0, then increase by 10
  for (buffer_size in buffer_sizes) {
    
    if ( buffer_size > 0 ){
      cat("Trying buffer size:", buffer_size, "\n")
    }
    
    
    # # Apply buffer (start with 0, then increase if needed)
    # if ( buffer_size == 0 ){
    #   buffered_geometry <- geometry
    # } else{
    #   buffered_geometry <- buffer(geometry, buffer_size)
    # }
    # Try executing the split
    buffered_geometry <- st_buffer(geometry, buffer_size)
    result <- tryCatch({
      split_result <- lwgeom::st_split(buffered_geometry, final_line) %>%
        st_collection_extract("POLYGON") %>%
        st_as_sf() %>%
        st_transform(7755) %>%
        mutate(polygon_id = 1:nrow(.),
               area = st_area(.))
      
      # If successful, return the result immediately
      return(split_result)
      
    }, error = function(e) {
      cat("Error encountered, increasing buffer size...\n")
      return(NULL)  # Continue loop if an error occurs
    })
    
    # If successful, exit the loop and return the result
    if (!is.null(result)) {
      return(result)
    }
  }
  
  # If all attempts fail, return NULL
  cat("All attempts failed. Check the input geometries.\n")
  return(NULL)
}

crs_use <- 7755
temp <- st_transform( temp, crs_use )
find_downwind <- function(grid_cell) {
  
  st_ends_heading <- function(line)
  {
    M <- sf::st_coordinates(line)
    i <- c(2, nrow(M) - 1)
    j <- c(1, -1)
    
    headings <- mapply(i, j, FUN = function(i, j) {
      Ax <- M[i-j,1]
      Ay <- M[i-j,2]
      Bx <- M[i,1]
      By <- M[i,2]
      unname(atan2(Ay-By, Ax-Bx))
    })
    
    return(headings)
  }
  st_extend_line <- function(line, distance, end = "BOTH")
  {
    if (!(end %in% c("BOTH", "HEAD", "TAIL")) | length(end) != 1) stop("'end' must be 'BOTH', 'HEAD' or 'TAIL'")
    
    M <- sf::st_coordinates(line)[,1:2]
    keep <- !(end == c("TAIL", "HEAD"))
    
    ends <- c(1, nrow(M))[keep]
    headings <- st_ends_heading(line)[keep]
    distances <- if (length(distance) == 1) rep(distance, 2) else rev(distance[1:2])
    
    M[ends,] <- M[ends,] + distances[keep] * c(cos(headings), sin(headings))
    newline <- sf::st_linestring(M)
    
    # If input is sfc_LINESTRING and not sfg_LINESTRING
    if (is.list(line)) newline <- sf::st_sfc(newline, crs = sf::st_crs(line))
    
    return(newline)
  }
  
  crs_use <- 7755
  geometry <- st_buffer( st_transform( grid_cell$centroid, 
                                       7755 ), 
                         dist = 13000 ) %>% 
    st_transform(7755)
  
  
  # Convert MULTIPOLYGON to POLYGON (if needed)
  if (any(st_geometry_type(geometry) == "GEOMETRYCOLLECTION")) {
    geometry <- st_cast(geometry)
    geometry$area <- st_area(geometry)
    geometry <- st_make_valid(geometry[which.max(geometry$area), ])
    geometry <- geometry[, !colnames(geometry) %in% "area"]
    
  }
  
  if (any(st_geometry_type(geometry) == "MULTIPOLYGON")) {
    geometry <- st_cast(geometry, "POLYGON")
    geometry$area <- st_area(geometry)
    geometry <- st_make_valid(geometry[which.max(geometry$area), ])
    geometry <- geometry[, !colnames(geometry) %in% "area"]
  }
  
  
  if (!anyNA(grid_cell$rollav_wind_direction_cellid_month)) {
    #bounding box of polygon
    bbox <- st_bbox(geometry)
    
    #calculate angles orthogonal to the direction of wind and create line that passes through grid point
    #spans the bounding box 
    lineLength <- st_length(
      st_linestring( rbind(c( bbox["xmin"], bbox["ymin"] ), 
                           c( bbox["xmax"], bbox["ymax"] ) ) ) %>% 
        st_sfc( crs = crs_use ) )
    angle1 <- grid_cell$rollav_wind_direction_cellid_month + 90
    point1_aux <- geosphere::destPoint(st_transform(grid_cell, 4326)$centroid %>% 
                                         st_coordinates(), angle1, lineLength*2) %>% 
      st_point() %>% 
      st_sfc() %>% 
      st_set_crs( 4326) %>% 
      st_transform(7755)
    
    point1 <- st_coordinates(point1_aux)
    line1 <- st_linestring(rbind(st_coordinates(grid_cell), point1)) %>% 
      st_sfc(crs = 7755)
    
    final_line <- st_extend_line(sf::st_geometry(line1), 100000000 )
    
    #split district along the line created in the previous section and  calculate area for each 
    #polygon, centers of polygons and bearing relative to the grid cell
    
    
    split_stp1 <- attempt_split(geometry, final_line)
    
    centroid_coord <- split_stp1 %>% 
      st_transform(7755) %>% 
      st_centroid(.) %>%
      st_transform(4326) %>% 
      st_coordinates()
    
    grid_coord <- grid_cell$centroid  %>% 
      st_transform(4326) %>% 
      st_coordinates()
    
    split <- split_stp1 %>% 
      mutate( bearing_relative = bearing( grid_coord, 
                                          centroid_coord ) )
    
    r.vals <- raster::extract(pop_raster, split, fun = sum, na.rm = TRUE, small = FALSE  )
    
    # Check if r.vals is a list
    if (is.list(r.vals)) {
      # Convert NULL list elements to 0
      r.vals <- lapply(r.vals, function(x) if (is.null(x)) 0 else x)
      
      # Convert list to numeric vector
      r.vals <- unlist(r.vals)
    }
    
    #determine whether each polygon is upwind or downwind by comparing the location of 
    #its center to the direction of wind
    split_1 <- split %>% 
      mutate(population = r.vals %>% round(0),
             downwind = if_else((bearing_relative < (grid_cell$rollav_wind_direction_cellid_month + 90)) & 
                                  (bearing_relative > (grid_cell$rollav_wind_direction_cellid_month - 90)), 1, 0))
    
    #determine whether each polygon is upwind or downwind by comparing the location of 
    #its center to the direction of wind
    r.vals2 <- raster::extract(pop_raster, split, fun = sum, na.rm = TRUE  )
    split_2 <- split %>% 
      mutate(population = r.vals2 %>% round(0),
             downwind = if_else((bearing_relative < (grid_cell$rollav_wind_direction_cellid_month + 90)) & 
                                  (bearing_relative > (grid_cell$rollav_wind_direction_cellid_month - 90)), 1, 0))
    
    
    return(data.frame(downwind_area_13kmpl_small = sum(split_1[which(split_1$downwind == 1), "area"]$area, na.rm = TRUE ),
                      upwind_area_13kmpl_small = sum(split_1[which(split_1$downwind == 0), "area"]$area, na.rm = TRUE ),
                      downwind_pop_13kmpl_small = sum(split_1[which(split_1$downwind == 1), "population"]$population, na.rm = TRUE ),
                      upwind_pop_13kmpl_small = sum(split_1[which(split_1$downwind == 0), "population"]$population, na.rm = TRUE ),
                      downwind_area_13kmpl_nosmall = sum(split_2[which(split_2$downwind == 1), "area"]$area, na.rm = TRUE ),
                      upwind_area_13kmpl_nosmall = sum(split_2[which(split_2$downwind == 0), "area"]$area, na.rm = TRUE ),
                      downwind_pop_13kmpl_nosmall = sum(split_2[which(split_2$downwind == 1), "population"]$population, na.rm = TRUE ),
                      upwind_pop_13kmpl_nosmall = sum(split_2[which(split_2$downwind == 0), "population"]$population, na.rm = TRUE ) 
                      
    )  )
  }
  return(data.frame(downwind_area_13kmpl_small = NA,
                    upwind_area_13kmpl_small = NA,
                    downwind_pop_13kmpl_small = NA,
                    upwind_pop_13kmpl_small = NA, 
                    downwind_area_13kmpl_nosmall = NA,
                    upwind_area_13kmpl_nosmall = NA,
                    downwind_pop_13kmpl_nosmall = NA,
                    upwind_pop_13kmpl_nosmall = NA))
}

n_obs <- dim(all_df)[1]
# n_obs <- 50


for ( i in 1:n_obs ){
  grid <- temp[i, ]
  if ( i == 1 ){
    df1 <- find_downwind( grid )
  } else{
    df2 <- find_downwind( grid )
    df1 <- rbind(df1, df2)
  }
  # print(i)
  if ( i %% 1000 == 0){
    print(i)
  }
}


if (nrow(all_df) == nrow(df1)) {
  all_df <- cbind(all_df, df1)
  path <- file.path(save_path, paste0( idx, ".RDS") )
  saveRDS( all_df, path )
  
} else {
  warning("all_df and df1 do not have the same number of rows. cbind() was not performed.")
}



