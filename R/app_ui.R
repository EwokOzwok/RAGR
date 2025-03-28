#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @import shinyMobile
#' @import shinyjs
#' @import jsonlite
#' @noRd
app_ui <- function(request) {
  tagList(
    # Leave this function for adding external resources
    golem_add_external_resources(),

    # tags$head(HTML('<link rel="stylesheet" type="text/css" href="framework7.bundle.min.css">')),
    # Your application UI logic

    shinyMobile::f7Page(
      title = "ragR",
      options = list(theme=c("auto"), dark=TRUE, preloader = T,  pullToRefresh=F),
      allowPWA=F,
      # Custom 'Generating Note' Message UI
      useShinyjs(),
      uiOutput("loading_screen"),
      uiOutput("busy_message"),


      # uiOutput("busy_message"),

      f7TabLayout(

        navbar = f7Navbar(
          title= "ragR"),

        f7Tabs(
          animated = TRUE,
          id = "tabs",
          f7Tab(
            tabName = "ragR",
            icon = f7Icon("house_fill"),
            active = TRUE,
            hidden= F,
            uiOutput("StepOne"),
            uiOutput("StepTwo"),
            uiOutput("StepThree"),
            uiOutput("StepFour"),
          )
        )
      )
    )

  )
}

#' Add external Resources to the Application
#'
#' This function is internally used to add external
#' resources inside the Shiny application.
#'
#' @import shiny
#' @importFrom golem add_resource_path activate_js favicon bundle_resources
#' @noRd
golem_add_external_resources <- function() {
  # add_resource_path(
  #   "www",
  #   app_sys("app/www")
  # )


  tags$head(
    tags$script(HTML("
  Shiny.addCustomMessageHandler('redirect', function(message) {
    window.location.href = message.url;
  });
")),


    tags$script(HTML("
        $(document).on('click', '#refresh_page', function() {
          location.reload();  // Reload the current page
        });
      ")),





    # favicon("https://ewokozwok.github.io/MassBaselineCleaner/gifs/ng_favicon"),
    tags$link(rel = "icon", type = "image/x-icon", href = "https://ewokozwok.github.io/MassBaselineCleaner/gifs/h2s_icon.ico"),

    # Include Swiper CSS and JS
    tags$link(rel = "stylesheet", href = "https://unpkg.com/swiper/swiper-bundle.min.css"),
    tags$script(src = "https://unpkg.com/swiper/swiper-bundle.min.js"),
    tags$link(rel = "stylesheet", href = "https://cdnjs.cloudflare.com/ajax/libs/sweetalert/2.1.2/sweetalert.min.css"),
    tags$script(src = "https://cdnjs.cloudflare.com/ajax/libs/sweetalert/2.1.2/sweetalert.min.js"),


    HTML('<link rel="stylesheet" type="text/css" href="https://ewokozwok.github.io/myexternalresources/framework7.bundle.min.css">')


  )
}
