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
            f7Align(h3("Step 1: Upload a .pdf to chat with (~200pg MAX)"), side = c("center")),
            br(),

            # Hidden file input
            tags$input(id = "fileInput", type = "file", style = "display: none;"),

            # Placeholder for custom error message
            div(id = "custom-error", class = "upload-error", style = "display: none; color: red;"),

            # Drag-and-Drop Zone
            div(id = "dropzone",
                "Drag & drop your PDF here or click to upload",
                style = "border: 2px dashed #ccc;
                        padding: 20px;
                        text-align: center;
                        cursor: pointer;
                        margin: 10px;  /* Adjusted margins */
                        box-sizing: border-box;
                        width: calc(100% - 20px);  /* Subtract total horizontal margin */
                        max-width: 100%;
                        overflow: hidden;  /* Prevent content from overflowing */
                        word-wrap: break-word;  /* Break long words if necessary */
                        white-space: normal;  /* Allow text to wrap */"),
            # JavaScript to handle drag-and-drop functionality with enhancements
            tags$script(HTML("
        $(document).ready(function() {
            var dropzone = $('#dropzone');
            var fileInput = $('#fileInput');

            // Open file picker on click
            dropzone.on('click', function() {
                fileInput.click();
            });

            // Handle file selection via file input
            fileInput.on('change', function(e) {
                var files = e.target.files;
                if (files.length > 0) {
                    uploadFile(files[0]);
                }
            });

            // Drag-over event to allow dropping
            dropzone.on('dragover', function(e) {
                e.preventDefault();
                e.stopPropagation();
                dropzone.addClass('drag-over');
            });

            // Drag-leave event
            dropzone.on('dragleave', function(e) {
                dropzone.removeClass('drag-over');
            });

            // Drop event
            dropzone.on('drop', function(e) {
                e.preventDefault();
                e.stopPropagation();
                dropzone.removeClass('drag-over');

                var files = e.originalEvent.dataTransfer.files;
                if (files.length > 0) {
                    uploadFile(files[0]);
                }
            });

            function uploadFile(file) {
                var formData = new FormData();
                formData.append('file', file);

                // Show loading icon and text
                $('#loading-icon').show();
                $('#custom-error').text('Uploading...').show();

                $.ajax({
                    url: 'https://ng.cliniciansfirst.org/ragr_upload', // Your Plumber API endpoint
                    type: 'POST',
                    data: formData,
                    processData: false,
                    contentType: false,
                    success: function(response) {
                        console.log('File uploaded successfully:', response);
                        // Hide error text and show success message or indicator
                        $('#custom-error').text('Upload successful!').show();
                        Shiny.setInputValue('upload_complete', true, {priority: 'event'});
                    },
                    error: function(xhr, status, error) {
                        console.error('File upload failed:', error);
                        // Display error only if upload fails
                        $('#custom-error').text('File upload failed.').show();
                    },
                    complete: function() {
                        // Hide loading icon after upload (whether success or error)
                        $('#loading-icon').hide();
                    }
                });
            }
        });
      "))
          )
        )
      )
    )
  })
      observeEvent(input$upload_complete, {
        output$StepOne <- renderUI({})
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

        # output$StepTwo <- renderUI({
        #   tagList(
        #     f7Block(
        #       f7Shadow(
        #         intensity = 5,
        #         hover = TRUE,
        #         f7Card(
        #           f7Align(h3("PDF Successfully Uploaded!"), side = c("center")),
        #           br(),
        #           f7Button("start_rag", "Initialize PDF")
        #         )
        #       )
        #     )
        #   )
        # })
      })



  # observeEvent(input$start_rag,{
  #
  #   rag_data <- list(
  #     text = pdf_text_content()
  #   )
  #
  #   # Make async HTTP request
  #   promise <- future({
  #     tryCatch({
  #       response <- POST(
  #         "https://ng.cliniciansfirst.org/start_rag",
  #         body = toJSON(rag_data, auto_unbox = TRUE),
  #         encode = "json",
  #         content_type_json()
  #       )
  #       content(response, "parsed")
  #     }, error = function(e) {
  #       stop(e)
  #     })
  #   })
  #
  #   resolve_promise(
  #     promise,
  #     success = function(result) {
  #       print(result$status)
  #
  #       if (result$status == "SUCCESS") {
  #         output$StepOne <- renderUI({})
  #         output$StepTwo <- renderUI({})
  #         output$StepThree <- renderUI({
  #           tagList(
  #             f7Block(
  #               f7Shadow(
  #                 intensity = 5,
  #                 hover = TRUE,
  #                 f7Card(
  #                   f7Align(h3("PDF Successfully Initialized!"), side = c("center")),
  #                   br(),
  #                   f7Button("start_chat", "Start Chatting with your PDF"),
  #                 )
  #               )
  #             )
  #           )
  #         })
  #
  #
  #
  #       }
  #     },
  #     error = function(err) {
  #       ServerError <- paste("Error in communication with the server.", err, sep = " ")
  #       print(ServerError)
  #     }
  #   )
  #
  #
  # })

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
    print(Prompt)
    sanitize_input <- function(input) {
      iconv(input, from = "UTF-8", to = "ASCII", sub = "") # Remove non-ASCII characters
    }
    # Prompt <- sanitize_input(Prompt)
    promise <- future({
      tryCatch({
        print("Starting POST request...")
        response <- POST(
          "https://ng.cliniciansfirst.org/process_ragr",
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

        # Use a slight delay and more robust scrolling method
        runjs('
        setTimeout(function() {
          var chatLog = document.getElementById("chat_log");
          if (chatLog) {
            chatLog.scrollTop = chatLog.scrollHeight;
          }
        }, 50);
      ')
        # Hide the preloader after the answer is received
        runjs("$('#custom-preloader').fadeOut();")
      },
      error = function(err) {
        # In case of error, hide the loading message and show an alert
        print(paste("Promise rejected with error:", err$message))
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
# observeEvent(input$submit_prompt,{
#   req(input$user_input)
#   user_input = paste("<br><b>User:</b>", input$user_input)
#   chat_log(paste(chat_log(),user_input, sep = ""))
#   updateF7TextArea("user_input", value = "",  placeholder = "Type here!", session = session)
#
#   # Show the custom preloader when the button is pressed
#   runjs("$('#custom-preloader').fadeIn();")
#
#
#   # Send the prompt to the Flask model
#   Answer <- ""
#
#   Prompt <- input$user_input
#   print(Prompt)
#
#   sanitize_input <- function(input) {
#     iconv(input, from = "UTF-8", to = "ASCII", sub = "") # Remove non-ASCII characters
#   }
#
#   # Prompt <- sanitize_input(Prompt)
#
#   promise <- future({
#     tryCatch({
#       print("Starting POST request...")
#
#       response <- POST(
#         "https://ng.cliniciansfirst.org/process_ragr",
#         body = toJSON(list(prompt_text = Prompt), auto_unbox = TRUE),
#         encode = "json",
#         content_type_json()
#       )
#
#       print("POST request completed.")
#       content(response, "parsed", encoding = "UTF-8")
#     }, error = function(e) {
#       print(paste("Error during POST request:", e$message))
#       stop(e)
#     })
#   })
#
#   resolve_promise(
#     promise,
#     success = function(result) {
#       # Hide the loading message and update the text area with the response
#       print("Promise resolved successfully.")
#       ragr_response <- as.character(result$result)
#       print(ragr_response)
#       ragr_response = paste("<br><b>ragR:</b>", ragr_response)
#       chat_log(paste(chat_log(),ragr_response, sep = ""))
#
#       # Wait until content is fully updated before scrolling to the bottom
#       runjs('
#         var chatLog = document.getElementById("chat_log");
#         chatLog.scrollTop = chatLog.scrollHeight;
#       ')
#
#       # Hide the preloader after the answer is received
#       runjs("$('#custom-preloader').fadeOut();")
#     },
#     error = function(err) {
#       # In case of error, hide the loading message and show an alert
#       print(paste("Promise rejected with error:", err))
#       runjs("$('#custom-preloader').fadeOut();")
#       showModal(modalDialog(
#         title = "Error",
#         paste("An error occurred while processing your request:", err$message),
#         easyClose = TRUE,
#         footer = NULL
#       ))
#     }
#   )
#
#
#
# })

output$loading_screen <- renderUI({
  tagList(
    tags$head(
      # Add custom CSS if needed
      tags$style(HTML("
        #loading-icon {
          position: fixed;
          top: 25%;
          left: 50%;
          transform: translate(-50%, -50%);
          display: none;
          z-index: 9999;
        }
      "))
    ),
    # The loading icon div
    tags$div(
      id = "loading-icon",
      tags$img(
        src = "https://ewokozwok.github.io/myexternalresources/bars-scale.svg",
        alt = "Uploading..."
      )
    )
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
