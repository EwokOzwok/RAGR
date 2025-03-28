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


  pdf_text_content = reactiveVal("")
  chat_log = reactiveVal("<b>ragR:</b> Now I am become PDF, destroyer of copy-paste!")

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

    # Use a more explicit temporary file path
    upload_dir <- "/tmp/shiny-uploads"

    # Ensure the directory exists
    if (!dir.exists(upload_dir)) {
      dir.create(upload_dir, recursive = TRUE, mode = "0777")
    }

    # Create a new filename to avoid conflicts
    tmp_file <- file.path(upload_dir, paste0("upload_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_", input$file$name))

    # Copy the uploaded file to the new location
    file.copy(input$file$datapath, tmp_file, overwrite = TRUE)

    # Verify file exists and is readable
    if (file.exists(tmp_file)) {
      # Set permissions to ensure readability
      Sys.chmod(tmp_file, mode = "0666")

      # Proceed with processing the PDF
      text <- tryCatch({
        pdf_text(tmp_file)
      }, error = function(e) {
        # Log the full error for debugging
        print(paste("PDF processing error:", e$message))
        showNotification("Error processing PDF. Please try again.", type = "error")
        return(NULL)
      })

      if (!is.null(text)) {
        pdf_text_content(text)

        # Optional: Clean up the temporary file after processing
        # Uncomment if you want to remove the file after use
        # on.exit(unlink(tmp_file))
      }
    } else {
      showNotification("Could not save uploaded file. Check permissions.", type = "error")
    }
  })
  # observe({
  #   req(input$file)  # Ensure a file is uploaded before proceeding
  #
  #   Sys.sleep(0.5)  # Adjust as necessary, but be cautious with responsiveness
  #
  #   # Save the uploaded file to a temporary location
  #   tmp_file <- input$file$datapath
  #
  #   # Check if the file exists before proceeding
  #   if (file.exists(tmp_file)) {
  #     # Proceed with processing the PDF
  #     text <- tryCatch({
  #       pdf_text(tmp_file)
  #     }, error = function(e) {
  #       showNotification("Error processing PDF. Please try again.", type = "error")
  #       return(NULL)
  #     })
  #
  #     if (!is.null(text)) {
  #       pdf_text_content(text)
  #       # print(text)
  #
  #       output$StepTwo <- renderUI({
  #         tagList(
  #           f7Block(
  #             f7Shadow(
  #               intensity = 5,
  #               hover = TRUE,
  #               f7Card(
  #                 f7Align(h3("PDF Uploaded Successfully"), side = c("center")),
  #                 br(),
  #                 f7Button("start_rag", "Initialize PDF for Chat"),
  #               )
  #             )
  #           )
  #         )
  #       })
  #
  #
  #
  #     }
  #   } else {
  #     showNotification("Uploaded file not found. Please re-upload.", type = "error")
  #   }
  # })


  observeEvent(input$start_rag,{

    rag_data <- list(
      text = pdf_text_content()
    )

    # Make async HTTP request
    promise <- future({
      tryCatch({
        response <- POST(
          "https://evanozmat.com/start_rag",
          body = toJSON(rag_data, auto_unbox = TRUE),
          encode = "json",
          content_type_json()
        )
        content(response, "parsed")
      }, error = function(e) {
        stop(e)
      })
    })

    resolve_promise(
      promise,
      success = function(result) {
        print(result$status)

        if (result$status == "SUCCESS") {
          output$StepOne <- renderUI({})
          output$StepTwo <- renderUI({})
          output$StepThree <- renderUI({
            tagList(
              f7Block(
                f7Shadow(
                  intensity = 5,
                  hover = TRUE,
                  f7Card(
                    f7Align(h3("PDF Successfully Initialized!"), side = c("center")),
                    br(),
                    f7Button("start_chat", "Start Chatting with your PDF"),
                  )
                )
              )
            )
          })



        }
      },
      error = function(err) {
        ServerError <- paste("Error in communication with the server.", err, sep = " ")
        print(ServerError)
      }
    )


  })

  observeEvent(input$start_chat,{
    output$StepThree <- renderUI({})
    output$StepFour <- renderUI({
      tagList(
        f7Block(
          f7Shadow(
            intensity = 5,
            hover = TRUE,
            f7Card(
              f7Align(h3("Start Chatting!"), side = c("center")),
              br(),
              # Non-editable text box (Chat log)
              tags$div(
                id = "chat_log",
                style = "border: 1px solid #ccc; padding: 10px; height: 300px; overflow-y: scroll;",
                htmlOutput("display_text")
              ),
              br(),
              f7TextArea("user_input", "Talk to your PDF", placeholder = "Type here!", value = ""),
              br(),
              f7Button("submit_prompt", "Submit")
            )
          )
        )
      )
    })


  })



  output$display_text <- renderUI({
    HTML(chat_log())
  })

observeEvent(input$submit_prompt,{
  req(input$user_input)
  user_input = paste("<br><b>User:</b>", input$user_input)
  chat_log(paste(chat_log(),user_input, sep = ""))
  updateF7TextArea("user_input", value = "",  placeholder = "Type here!", session = session)

  # Show the custom preloader when the button is pressed
  runjs("$('#custom-preloader').fadeIn();")


  # Send the prompt to the Flask model
  Answer <- ""

  Prompt <- input$user_input

  sanitize_input <- function(input) {
    iconv(input, from = "UTF-8", to = "ASCII", sub = "") # Remove non-ASCII characters
  }

  Prompt <- sanitize_input(Prompt)

  print(Prompt)
  promise <- future({
    tryCatch({
      print("Starting POST request...")

      response <- POST(
        "https://evanozmat.com/process_ragr",
        body = toJSON(list(prompt_text = Prompt), auto_unbox = TRUE),
        encode = "json",
        content_type_json()
      )

      print("POST request completed.")
      content(response, "parsed", encoding = "UTF-8")
    }, error = function(e) {
      print(paste("Error during POST request:", e$message))
      stop(e)
    })
  })

  resolve_promise(
    promise,
    success = function(result) {
      # Hide the loading message and update the text area with the response
      print("Promise resolved successfully.")
      ragr_response <- as.character(result$result)
      print(ragr_response)
      ragr_response = paste("<br><b>ragR:</b>", ragr_response)
      chat_log(paste(chat_log(),ragr_response, sep = ""))


      # Hide the preloader after the answer is received
      runjs("$('#custom-preloader').fadeOut();")
    },
    error = function(err) {
      # In case of error, hide the loading message and show an alert
      print(paste("Promise rejected with error:", err))
      runjs("$('#custom-preloader').fadeOut();")
      showModal(modalDialog(
        title = "Error",
        paste("An error occurred while processing your request:", err$message),
        easyClose = TRUE,
        footer = NULL
      ))
    }
  )



})



output$busy_message <- renderUI({
  # Custom Pre Loader Message
  tagList(
    tags$head(
      tags$style(
        HTML("
        #custom-preloader {
          position: fixed;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          display: none; /* Initially hidden */
          justify-content: center;
          align-items: center;
          background: rgba(0, 0, 0, 0.8);
          color: white;
          font-size: 1.5em;
          z-index: 9999;
        }
      ")
      ),
      tags$script(
        HTML("
        $(document).on('shiny:busy', function() {
          $('#custom-preloader').fadeIn(); // Show when Shiny is busy
        });

        $(document).on('shiny:idle', function() {
          $('#custom-preloader').fadeOut(); // Hide when Shiny is idle
        });

        $(document).ready(function() {
          // Change message after specific time intervals
          setTimeout(function() {
            $('#custom-preloader').html('<div style=\"text-align: center;\">We use a cutting edge 7-Billion parameter model...<br>It takes some time to generate, but it\'s worth the wait!</div>');
          }, 300000); // 30 seconds
        });
      ")
      )
    ),
    # The preloader div
    div(
      id = "custom-preloader",
      HTML('<div style="text-align: center;">Generating your answer now...<br>This usually takes less than 1 minute</div>')
    )
  )
})



}
