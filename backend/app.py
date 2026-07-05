import os
from flask import Flask, request, jsonify
from flask_cors import CORS

from langchain_community.document_loaders import PyPDFLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_community.vectorstores import FAISS

import requests

app = Flask(__name__)
CORS(app)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
# Temp upload folder now lives INSIDE the container instead of
# /mnt/c/Users/Admin/Desktop/Ragr/temp on the host machine.
UPLOAD_FOLDER = os.environ.get("RAGR_UPLOAD_FOLDER", "/app/backend/temp")
VLLM_URL = os.environ.get("VLLM_URL", "https://www.evanozmat.com/llama/v1/chat/completions")

os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
new_vector_store = None

embeddings = HuggingFaceEmbeddings(
    model_name="sentence-transformers/all-MiniLM-L6-v2",
    model_kwargs={"device": "cpu"}
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def process_pdf(pdf_path):
    """Load and split a PDF into a FAISS vector store."""
    loader = PyPDFLoader(pdf_path)
    documents = loader.load()

    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200
    )
    chunks = text_splitter.split_documents(documents)
    vector_store = FAISS.from_documents(chunks, embeddings)
    print(f"Vector store created with {len(chunks)} chunks")
    return vector_store


def query_vllm(prompt, model_name="nemo-base"):
    """Send a chat completion request to the vLLM API server."""
    payload = {
        "model": model_name,
        "messages": [
            {"role": "system", "content": "You are a helpful assistant that uses the provided text context to answer accurately."},
            {"role": "user", "content": prompt}
        ],
        "max_tokens": 800,
        "temperature": 1.0,
        "top_p": 0.9,
        "top_k": 25,
        "repetition_penalty": 1.1
    }
    headers = {"Content-Type": "application/json"}
    try:
        response = requests.post(VLLM_URL, json=payload, headers=headers, timeout=120)
        response.raise_for_status()
        result = response.json()
        return result["choices"][0]["message"]["content"]
    except Exception as e:
        print(f"Error communicating with vLLM: {e}")
        return f"Error: {str(e)}"


def query_rag(prompt_text, vector_store, k=8):
    """Retrieve relevant chunks from the vector store and query vLLM with them."""
    if vector_store is None:
        return "Error: No vector store initialized."

    docs = vector_store.similarity_search(prompt_text, k=k)
    context = "\n\n".join([doc.page_content for doc in docs])

    full_prompt = (
        f"Use the following text to answer the question below accurately and concisely.\n\n"
        f"Context:\n{context}\n\n"
        f"Question: {prompt_text}"
    )
    return query_vllm(full_prompt)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.route('/process_ragr', methods=['POST'])
def process_prompt():
    global new_vector_store
    data = request.get_json()
    prompt_text = data.get('prompt_text', '')

    if not prompt_text:
        return jsonify({"error": "No prompt_text provided"}), 400

    print(f"RAG Query: {prompt_text}")

    try:
        result = query_rag(prompt_text, new_vector_store)
        return jsonify({"result": result})
    except Exception as e:
        print(f"Error processing RAG request: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/ragr_upload', methods=['POST'])
def ragr_upload():
    global new_vector_store

    if 'file' not in request.files:
        return jsonify({"status": "FAILED", "message": "No file uploaded"}), 400

    file = request.files['file']

    if file.filename == '':
        return jsonify({"status": "FAILED", "message": "No selected file"}), 400

    # Save to the container-local temp folder
    file_path = os.path.join(app.config["UPLOAD_FOLDER"], file.filename)
    file.save(file_path)

    try:
        new_vector_store = process_pdf(file_path)
        print(new_vector_store)
        status = "SUCCESS"
        os.remove(file_path)
    except Exception as e:
        status = "FAILED"
        print(f"Error processing PDF: {e}")

    return jsonify({"status": status, "file": file.filename})


@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        "status": "running",
        "general_vector_store_loaded": new_vector_store is not None
    })


if __name__ == '__main__':
    print("\nStarting Flask server...")
    print("Server ready! Listening on http://0.0.0.0:5099")
    app.run(host='0.0.0.0', port=5099, debug=False)