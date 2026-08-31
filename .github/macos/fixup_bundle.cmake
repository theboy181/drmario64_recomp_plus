include(BundleUtilities)

if(NOT DEFINED APP_EXECUTABLE)
    message(FATAL_ERROR "APP_EXECUTABLE was not provided")
endif()

if(NOT DEFINED APP_BUNDLE)
    message(FATAL_ERROR "APP_BUNDLE was not provided")
endif()

set(SEARCH_DIRS
    "${APP_BUNDLE}/Contents/Frameworks"
    "/opt/homebrew/lib"
    "/usr/local/lib"
)

if(DEFINED BUNDLE_LIBRARY_DIR AND BUNDLE_LIBRARY_DIR)
    list(PREPEND SEARCH_DIRS "${BUNDLE_LIBRARY_DIR}")
endif()

fixup_bundle("${APP_EXECUTABLE}" "" "${SEARCH_DIRS}")
