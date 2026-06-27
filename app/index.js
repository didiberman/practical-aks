const express = require('express');
const fs = require('fs');
const path = require('path');
const { DefaultAzureCredential } = require('@azure/identity');
const { SecretClient } = require('@azure/keyvault-secrets');
const { GoogleGenAI } = require('@google/genai');

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 8080;
const MODEL_NAME = process.env.MODEL_NAME || 'gemini-2.5-flash';

// Helper function to read the system prompt template (for MLOps versioning)
function loadSystemPrompt() {
  try {
    const promptPath = path.join(__dirname, 'prompts', 'system_prompt.txt');
    if (fs.existsSync(promptPath)) {
      return fs.readFileSync(promptPath, 'utf8').trim();
    }
  } catch (err) {
    console.error('Failed to load system prompt:', err);
  }
  return 'You are a helpful assistant.';
}

const systemPrompt = loadSystemPrompt();

// Helper to acquire the API key (from local env or Azure Key Vault via Workload Identity)
async function getApiKey() {
  // 1. Fallback for local development or direct injects
  if (process.env.GEMINI_API_KEY) {
    console.log('Using API key from local environment variable.');
    return process.env.GEMINI_API_KEY;
  }

  // 2. Azure Key Vault retrieval using Workload Identity (DefaultAzureCredential)
  const keyVaultUri = process.env.KEY_VAULT_URI;
  const secretName = process.env.GEMINI_API_KEY_SECRET_NAME || 'gemini-api-key';

  if (!keyVaultUri) {
    throw new Error('Missing configuration: GEMINI_API_KEY or KEY_VAULT_URI must be set.');
  }

  console.log(`Fetching secret "${secretName}" from Key Vault: ${keyVaultUri}`);
  
  // DefaultAzureCredential automatically uses Workload Identity credentials inside AKS
  const credential = new DefaultAzureCredential();
  const client = new SecretClient(keyVaultUri, credential);
  const secret = await client.getSecret(secretName);
  return secret.value;
}

// Format LLM prompts using versioned templates
function formatPrompt(userInput) {
  if (!userInput || typeof userInput !== 'string' || userInput.trim() === '') {
    throw new Error('Input prompt cannot be empty.');
  }
  return userInput.trim();
}

// API endpoint to generate content
app.post('/api/generate', async (req, res) => {
  const startTime = Date.now();
  try {
    const { prompt } = req.body;
    const cleanPrompt = formatPrompt(prompt);

    // Dynamic API key resolution
    const apiKey = await getApiKey();
    const ai = new GoogleGenAI({ apiKey: apiKey });

    console.log(`Sending prompt to model: ${MODEL_NAME}`);
    const response = await ai.models.generateContent({
      model: MODEL_NAME,
      contents: cleanPrompt,
      config: {
        systemInstruction: systemPrompt,
      }
    });

    const durationMs = Date.now() - startTime;

    // Return response along with MLOps tracking metadata
    res.json({
      text: response.text,
      metadata: {
        model: MODEL_NAME,
        latencyMs: durationMs,
        promptLength: cleanPrompt.length,
        timestamp: new Date().toISOString()
      }
    });
  } catch (err) {
    console.error('Generation failed:', err);
    res.status(500).json({
      error: 'Failed to generate content',
      details: err.message
    });
  }
});

app.get('/healthz', (req, res) => {
  res.status(200).send('OK');
});

// Expose formatting function and loader for testing
module.exports = { app, formatPrompt, loadSystemPrompt };

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`LLM service listening on port ${PORT}`);
  });
}
