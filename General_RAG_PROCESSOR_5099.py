import os
from flask import Flask, request, jsonify
from flask_cors import CORS

import json
import subprocess
import queue
import threading
import time
import re
from transformers import AutoTokenizer, AutoModelForTokenClassification, pipeline
import datetime
import torch
import gc
from nacl.secret import SecretBox
from nacl.exceptions import CryptoError
import base64
import numpy as np

# ExLlamaV2 imports
from exllamav2 import (
    ExLlamaV2,
    ExLlamaV2Config,
    ExLlamaV2Cache,
    ExLlamaV2Tokenizer,
)
from exllamav2.generator import (
    ExLlamaV2BaseGenerator,
    ExLlamaV2Sampler
)

from langchain_community.document_loaders import PyPDFLoader, TextLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_community.vectorstores import FAISS
from langchain.docstore.document import Document


# Global variables
model = None
cache = None
tokenizer = None
generator = None
secret_key = None
request_queue = queue.Queue()
new_vector_store = None

app = Flask(__name__)
CORS(app)  # enables CORS for all routes and all origins

# Thread-safe lock for model access
model_lock = threading.Lock()

def get_gpu_memory():
    """Print GPU memory usage"""
    if torch.cuda.is_available():
        print(f"GPU memory allocated: {torch.cuda.memory_allocated() / 1024**2:.2f} MB")
        print(f"GPU memory reserved: {torch.cuda.memory_reserved() / 1024**2:.2f} MB")

def initialize_model(model_path):
    global model, cache, tokenizer, generator

    with model_lock:
        try:
            print("Initializing model...")
            
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
                gc.collect()
            
            get_gpu_memory()
            
            config = ExLlamaV2Config()
            config.model_dir = model_path
            config.prepare()
            
            config.max_batch_size = 1
            
            print("Configuration prepared. GPU memory status:")
            get_gpu_memory()
            
            model = ExLlamaV2(config)
            tokenizer = ExLlamaV2Tokenizer(config)
            
            print("Model and tokenizer created. GPU memory status:")
            get_gpu_memory()
            
            print("Loading model with auto-split...")
            cache = ExLlamaV2Cache(model, lazy=True)
            model.load_autosplit(cache)
            
            print("Model loaded. GPU memory status:")
            get_gpu_memory()
            
            generator = ExLlamaV2BaseGenerator(model, cache, tokenizer)

            print("Warming up...")
            with torch.inference_mode():
                settings = ExLlamaV2Sampler.Settings()
                generator.generate_simple("Test", settings, 1)
            
            print("Model ready! Final GPU memory status:")
            get_gpu_memory()
            
            return generator
            
        except Exception as e:
            print(f"Error during initialization: {str(e)}")
            raise


def process_text(input_text):
    global new_vector_store

    """
    Process input text for vector search
    
    Args:
        input_text (str or list): Text to be processed for vector search
    
    Returns:
        FAISS vector store of text chunks
    """
    if isinstance(input_text, list):  
        input_text = "\n".join(input_text)  # Join list elements into a single string
    
    # Create a Document object from the input string
    documents = [Document(page_content=input_text)]
    
    # Split text into chunks
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200
    )
    chunks = text_splitter.split_documents(documents)
    
    # Create vector store for search
    embeddings = HuggingFaceEmbeddings(model_name="sentence-transformers/all-MiniLM-L6-v2")
    vector_store = FAISS.from_documents(chunks, embeddings)
    new_vector_store = vector_store
    return new_vector_store

def query_exllama(query, vector_store, tokens):
    """
    Thread-safe query method for ExLlamaV2 
    """
    # Retrieve relevant documents
    docs = vector_store.similarity_search(query, k=10)
    
    # Extract and join context
    context = "\n\n".join([doc.page_content for doc in docs])
    
    prompt = f"<s>[INST]Using the following Text Content, answer this question: {query}\n\nText Content:\n{context}[/INST]"
    
    # Ensure thread-safe generation
    with model_lock:
        try:        
            settings = ExLlamaV2Sampler.Settings()
            settings.temperature = 0.7
            settings.top_k = 10
            settings.token_repetition_penalty = 1.1
            
            with torch.inference_mode():
                output = generator.generate_simple(
                    prompt,
                    settings,
                    int(tokens),
                    token_healing=True
                )
                
                # Ensure output starts from the closest space before or at len(prompt)
                def clean_response(output, prompt):
                    start_idx = len(prompt)
                
                    # Find the closest space BEFORE or AT start_idx
                    match = re.search(r'\s', output[:start_idx][::-1])  # Search backward for the first space
                    if match:
                        start_idx -= match.start() + 1  # Adjust index to cut at the space
                
                    return output[start_idx:].strip()
                
                response = clean_response(output, prompt)
                
                # Clean up the output
                # response = output[len(prompt):].strip()
                
                torch.cuda.empty_cache()
                gc.collect()
                
                return response
        
        except Exception as e:
            print(f"Generation error: {str(e)}")
            raise


def process_request_worker():
    global new_vector_store
    """Worker function to process requests from the queue"""
    while True:
        try:
            # Get request from queue
            task = request_queue.get()
            if task is None:  # Poison pill to stop the worker
                break
                
            request_type, data, response_queue = task
            
            if request_type == "generate":
                prompt_text, new_tokens = data
                print(f"Processing prompt: {prompt_text}")
                
                # Ensure vector store exists
                if new_vector_store is None:
                    response_queue.put({"error": "Vector store not initialized"})
                    continue
                
                try:
                    result = query_exllama(prompt_text, new_vector_store, tokens=new_tokens)
                    response_queue.put({"result": result})  # Explicitly put result in queue
                except Exception as e:
                    response_queue.put({"error": str(e)})

        except Exception as e:
            print(f"Worker error: {str(e)}")
            response_queue.put({"error": str(e)})
        finally:
            request_queue.task_done()


def process_pdf(pdf_path):
    """
    Load and process PDF document for vector search
    """
    # Load PDF
    loader = PyPDFLoader(pdf_path)
    documents = loader.load()
    
    # Split documents into chunks
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200
    )
    chunks = text_splitter.split_documents(documents)
    embeddings = HuggingFaceEmbeddings(model_name="sentence-transformers/all-MiniLM-L6-v2")
    vector_store = FAISS.from_documents(chunks, embeddings)
    
    print(vector_store)

    return vector_store


@app.route('/process_ragr', methods=['POST'])
def process_prompt():
    data = request.get_json()
    prompt_text = data['prompt_text']
    
    if isinstance(prompt_text, list):  
        prompt_text = ' '.join(map(str, prompt_text))  # Convert list to string
    
    print(f"Data Received: {prompt_text}")
    
    new_tokens = 650  # Default value if conversion fails

    # Create a response queue for this request
    response_queue = queue.Queue()
    
    # Add task to request queue
    request_queue.put(("generate", (prompt_text, new_tokens), response_queue))
    
    # Wait for response with timeout
    try:
        result = response_queue.get(timeout=120)  # 60 seconds timeout
        return jsonify(result)
    except queue.Empty:
        return jsonify({"error": "Request timed out"}), 504

# @app.route('/start_rag', methods=['POST'])
# def start_rag():
#     global new_vector_store
#     data = request.get_json()
#     rag_text = data['text']
# 
# 
#     try:
#         new_vector_store = process_text(rag_text)
#         print(new_vector_store)
#         status = "SUCCESS"
#     except Exception as e:
#         status = "FAILED"
#         print(f"Error processing text: {e}")  # Log error for debugging
# 
#     return jsonify({"status": status})

@app.route('/ragr_upload', methods=['POST'])
def ragr_upload():
    global new_vector_store
    UPLOAD_FOLDER = "/mnt/c/Users/eo276194/Desktop/Ragr/temp"  # Change this to an existing path
    app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER
    # Check if a file is in the request
    if 'file' not in request.files:
        return jsonify({"status": "FAILED", "message": "No file uploaded"}), 400

    file = request.files['file']
    
    if file.filename == '':
        return jsonify({"status": "FAILED", "message": "No selected file"}), 400

    # Save the file to a temp directory
    file_path = os.path.join(app.config["UPLOAD_FOLDER"], file.filename)
    file.save(file_path)

    try:
        # Process the PDF file into vector store
        new_vector_store = process_pdf(file_path)  # Replace with your processing function
        print(new_vector_store)
        status = "SUCCESS"
        # Delete the temp file after successful processing
        os.remove(file_path)
    except Exception as e:
        status = "FAILED"
        print(f"Error processing PDF: {e}")

    return jsonify({"status": status, "file": file.filename})



if __name__ == '__main__':
    # Initialize the model before starting the server
    # initialize_model("/mnt/f/Models/v2/exllamaSepPrompts_8.0bpw/")
    initialize_model("/mnt/c/users/eo276194/desktop/Models/Mistral-7B-Instruct-v0.2_8.0bpw/")


    # Start worker threads
    num_workers = 4  # You can adjust this number based on your needs
    workers = []
    for _ in range(num_workers):
        worker = threading.Thread(target=process_request_worker, daemon=True)
        worker.start()
        workers.append(worker)
    
    app.run(host='0.0.0.0', port=5099, debug=False)
