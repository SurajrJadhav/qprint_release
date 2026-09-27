# Run at build time (-P) to copy SumatraPDF and LibreOffice into the output dir
# only if they exist. Does not fail the build if sources are missing.
# Usage: cmake -DSUMATRA_EXE=... -DLIBREOFFICE_DIR=... -DOUT_DIR=... -P copy_optional_bin.cmake

if(NOT OUT_DIR)
  message(WARNING "copy_optional_bin.cmake: OUT_DIR not set")
  return()
endif()

if(SUMATRA_EXE AND EXISTS "${SUMATRA_EXE}")
  message(STATUS "Copying SumatraPDF.exe to ${OUT_DIR}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${SUMATRA_EXE}" "${OUT_DIR}"
    RESULT_VARIABLE rv
  )
  if(NOT rv EQUAL 0)
    message(WARNING "Copy SumatraPDF.exe failed (${rv}); build continues.")
  endif()
endif()

set(LIBREOFFICE_SOFFICE "${LIBREOFFICE_DIR}/App/libreoffice/program/soffice.exe")
if(LIBREOFFICE_DIR AND EXISTS "${LIBREOFFICE_SOFFICE}")
  set(LIBREOFFICE_DEST "${OUT_DIR}/LibreOffice")
  message(STATUS "Copying LibreOffice to ${LIBREOFFICE_DEST}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E copy_directory "${LIBREOFFICE_DIR}" "${LIBREOFFICE_DEST}"
    RESULT_VARIABLE rv
  )
  if(NOT rv EQUAL 0)
    message(WARNING "Copy LibreOffice failed (${rv}); build continues.")
  endif()
endif()
