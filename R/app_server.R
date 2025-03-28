#' The application server-side
#'
#' @param input,output,session Internal parameters for {shiny}.
#'     DO NOT REMOVE.
#' @import shiny
#' @import shiny
#' @import future
#' @import httr
#' @import promises
#' @import pdftools
#' @import officer
#' @import shinyjs
#' @import jsonlite
#' @import callr
#' @import shinyMobile
#' @noRd
app_server <- function(input, output, session) {

  future::plan(future::multisession, workers = 4)
  options(future.rng.onMisuse = "ignore")

  # Define custom promise operators
  `%...>%` <- function(promise, success) {
    promise %>% promises::then(success)
  }

  `%...!%` <- function(promise, error) {
    promise %>% promises::catch(error)
  }

  # Resolve promise function
  resolve_promise <- function(promise, success, error = NULL) {
    if (is.null(error)) {
      promise %...>% success
    } else {
      promise %...>% success %...!% error
    }
  }


  # Updated Drag and Drop
  output$StepOne <- renderUI({
    tagList(

      # Adding custom CSS for the drag-and-drop zone
      tags$head(
        tags$style(HTML("
        #dropzone {
          width: 100%;
          height: 150px;
          border: 4px dashed #1b5377;
          border-radius: 10px;
          background-color: #00000;
          text-align: center;
          line-height: 150px;
          font-size: 18px;
          color: #46166B;
          transition: background-color 0.3s, border-color 0.3s;
        }

        #dropzone.drag-over {
          background-color: #1b5377;
          border-color: #1b5377;
          color: #FFFAFA;
        }

        #dropzone:hover {
          cursor: pointer;
        }

        .upload-error {
          color: red;
          font-size: 24px;
          text-align: center;
          margin-top: 10px;
        }

        #file {
          display: none;
        }
      "))
      ),

      # File input UI with drag-and-drop zone
      f7Block(
        f7Shadow(
          intensity = 5,
          hover = TRUE,
          f7Card(
            f7Align(h3("Step 1: Upload a .pdf of a Scientific Article or Book Chapter (~40pg MAX)"), side = c("center")),
            br(),
            # Drag-and-Drop Zone
            div(id = "dropzone", "Drag & drop your PDF here or click"),
            fileInput("file", label = NULL, accept = ".pdf", multiple = FALSE),  # Hiding original file input field

            # Placeholder for custom error message
            div(id = "custom-error", class = "upload-error", style = "display: none;"),

            # Placeholder for file upload status
            textOutput("status"),

            # JavaScript to handle drag-and-drop functionality with enhancements
            tags$script(HTML("
            $(document).on('dragover', function(e) {
              e.preventDefault();
              e.stopPropagation();
              $('#dropzone').addClass('drag-over');
            });

            $(document).on('dragleave', function(e) {
              e.preventDefault();
              e.stopPropagation();
              $('#dropzone').removeClass('drag-over');
            });

            $('#dropzone').on('drop', function(e) {
              e.preventDefault();
              e.stopPropagation();
              $('#dropzone').removeClass('drag-over');

              var files = e.originalEvent.dataTransfer.files;
              console.log('Files dropped:', files);  // Log dropped files for debugging

              // Set the dropped file to the fileInput with a slight delay
              setTimeout(function() {
                $('#file').prop('files', files);
                $('#file').trigger('change');
              }, 50);
            });

            $('#dropzone').on('click', function() {
              $('#file').click();  // Simulate file input click when dropzone is clicked
            });

            // Handle file input change and validate file size
            $('#file').on('change', function() {
              console.log('File input change triggered:', $(this)[0].files);  // Log file input change

              if ($(this)[0].files.length > 0) {
                var file = $(this)[0].files[0];
                if (file.size > 5048576) {  // Example max size of 1MB (adjust as needed)
                  $('#custom-error').text('Maximum upload size exceeded').show();
                } else {
                  $('#custom-error').hide();
                }
              } else {
                $('#custom-error').hide();
              }
            });
          "))
          )
        )
      )
    )
  })


  observe({
    req(input$file)  # Ensure a file is uploaded before proceeding

    Sys.sleep(0.5)  # Adjust as necessary, but be cautious with responsiveness

    # Save the uploaded file to a temporary location
    tmp_file <- input$file$datapath

    # Check if the file exists before proceeding
    if (file.exists(tmp_file)) {
      # Proceed with processing the PDF
      text <- tryCatch({
        pdf_text(tmp_file)
      }, error = function(e) {
        showNotification("Error processing PDF. Please try again.", type = "error")
        return(NULL)
      })

      if (!is.null(text)) {
        print(text)
      }
    } else {
      showNotification("Uploaded file not found. Please re-upload.", type = "error")
    }
  })

}
