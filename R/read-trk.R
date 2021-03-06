read_fixed_char_binary <- function(fh, n, to = "UTF-8") {
  txt <- readBin(fh, "raw", n)
  iconv(rawToChar(txt[txt != as.raw(0)]), to = to)
}

retrieve_trk_endianness <- function (input_file) {
  fh <- file(input_file, "rb")
  on.exit({
    close(fh)
  }, add = TRUE)
  seek(fh, where = 996L, origin = "start")
  endian <- "little"
  sizeof_hdr_little <- readBin(fh, integer(), n = 1, size = 4, endian = endian)
  if (sizeof_hdr_little == 1000L)
    return(endian)
  else {
    seek(fh, where = 996L, origin = "start")
    endian <- "big"
    sizeof_hdr_big <- readBin(fh, integer(), n = 1, size = 4, endian = endian)
    if (sizeof_hdr_big == 1000L)
      return(endian)
    else
      cli::cli_abort("File {.file {input_file}} is not in TRK format (header
                     sizes {sizeof_hdr_little}/{sizeof_hdr_big} in little/big
                     endian mode while 1000 was expected).")
  }
}

read_trk <- function(input_file) {
  endian <- retrieve_trk_endianness(input_file)
  fh <- file(input_file, "rb")
  on.exit({
    close(fh)
  }, add = TRUE)
  header                           <- list()
  header$id_string                 <- read_fixed_char_binary(fh, 6L)
  header$dim                       <- readBin(fh, integer(), n = 3, size = 2, endian = endian)
  header$voxel_size                <- readBin(fh, numeric(), n = 3, size = 4, endian = endian)
  header$origin                    <- readBin(fh, numeric(), n = 3, size = 4, endian = endian)
  header$n_scalars                 <- readBin(fh, integer(), n = 1, size = 2, endian = endian)
  header$scalar_names              <- read_fixed_char_binary(fh, 200L)
  header$n_properties              <- readBin(fh, integer(), n = 1, size = 2, endian = endian)
  header$property_names            <- read_fixed_char_binary(fh, 200L)
  header$vox2ras                   <- matrix(readBin(fh, numeric(), n = 16, size = 4, endian = endian), ncol = 4, byrow = TRUE)
  header$reserved                  <- read_fixed_char_binary(fh, 444L)
  header$voxel_order               <- read_fixed_char_binary(fh, 4L)
  header$pad2                      <- read_fixed_char_binary(fh, 4L)
  header$image_orientation_patient <- readBin(fh, numeric(), n = 6, size = 4, endian = endian)
  header$pad1                      <- read_fixed_char_binary(fh, 2L)
  header$invert_x                  <- readBin(fh, integer(), n = 1, size = 1, signed = FALSE, endian = endian)
  header$invert_y                  <- readBin(fh, integer(), n = 1, size = 1, signed = FALSE, endian = endian)
  header$invert_z                  <- readBin(fh, integer(), n = 1, size = 1, signed = FALSE, endian = endian)
  header$swap_xy                   <- readBin(fh, integer(), n = 1, size = 1, signed = FALSE, endian = endian)
  header$swap_yz                   <- readBin(fh, integer(), n = 1, size = 1, signed = FALSE, endian = endian)
  header$swap_zx                   <- readBin(fh, integer(), n = 1, size = 1, signed = FALSE, endian = endian)
  header$n_count                   <- readBin(fh, integer(), n = 1, size = 4, endian = endian)
  header$version                   <- readBin(fh, integer(), n = 1, size = 4, endian = endian)
  header$hdr_size                  <- readBin(fh, integer(), n = 1, size = 4, endian = endian)
  if (header$version != 2L)
    cli::cli_alert_warning("TRK file {.file {input_file}} has version {header$version}
                           while only version 2 is supported.")
  if (header$hdr_size != 1000L)
    cli::cli_alert_warning("TRK file {.file {input_file}} header field hdr_size is
                           {header$hdr_size}, must be 1000.")
  tracks <- lapply(1L:header$n_count, function(str_id) {
    num_points <- readBin(fh, integer(), n = 1, size = 4, endian = endian)
    current_track <- tibble::tibble(
      X = rep(0, num_points),
      Y = rep(0, num_points),
      Z = rep(0, num_points),
      PointId = 1:num_points,
      StreamlineId = str_id
    )
    current_track_coords <- matrix(rep(NA, (num_points * 3L)), ncol = 3)
    if (header$n_scalars > 0L) {
      current_track_scalars <- matrix(
        rep(NA, (num_points * header$n_scalars)),
        ncol = header$n_scalars
      )
      for (nm in header$scalar_names)
        current_track[nm] <- rep(0, num_points)
    }
    if (num_points > 0L) {
      for (track_point_idx in 1L:num_points) {
        current_track_coords[track_point_idx, ] <- readBin(
          fh, numeric(),
          n = 3,
          size = 4,
          endian = endian
        )
        current_track$X <- current_track_coords[, 1]
        current_track$Y <- current_track_coords[, 2]
        current_track$Z <- current_track_coords[, 3]
        if (header$n_scalars > 0L) {
          current_track_scalars[track_point_idx, ] <- readBin(
            fh, numeric(),
            n = header$n_scalars,
            size = 4,
            endian = endian
          )
          for (i in 1L:header$n_scalars)
            current_track[header$scalar_names[i]] <- current_track_scalars[, i]
        }
      }
    }
    if (header$n_properties > 0L) {
      current_track_properties <- matrix(
        readBin(
          fh, numeric(),
          n = header$n_properties,
          size = 4,
          endian = endian
        ),
        ncol = header$n_properties
      )
      for (i in 1L:header$n_properties)
        current_track[header$property_names[i]] <- current_track_properties[, i]
    }
    current_track
  })
  tracks <- Reduce(rbind, tracks)
  class(tracks) <- c("maf_df", class(tracks))
  tracks
}
