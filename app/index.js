const express = require('express');
const fs = require('fs');
const path = require('path');
const { DefaultAzureCredential } = require('@azure/identity');

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 8080;
const AZURE_OPENAI_ENDPOINT = process.env.AZURE_OPENAI_ENDPOINT;
const AZURE_OPENAI_DEPLOYMENT = process.env.AZURE_OPENAI_DEPLOYMENT || 'gpt-4o-mini';
const AZURE_OPENAI_API_VERSION = process.env.AZURE_OPENAI_API_VERSION || '2024-10-21';
const AZURE_OPENAI_SCOPE = 'https://cognitiveservices.azure.com/.default';

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

const credential = new DefaultAzureCredential();

// Format LLM prompts using versioned templates
function formatPrompt(userInput) {
  if (!userInput || typeof userInput !== 'string' || userInput.trim() === '') {
    throw new Error('Input prompt cannot be empty.');
  }
  return userInput.trim();
}

function buildAzureOpenAIUrl(endpoint, deployment, apiVersion) {
  if (!endpoint) {
    throw new Error('Missing configuration: AZURE_OPENAI_ENDPOINT must be set.');
  }

  const trimmedEndpoint = endpoint.replace(/\/+$/, '');
  const encodedDeployment = encodeURIComponent(deployment);
  return `${trimmedEndpoint}/openai/deployments/${encodedDeployment}/chat/completions?api-version=${apiVersion}`;
}

function decodeJwtPayload(token) {
  const [, payload] = token.split('.');
  if (!payload) {
    throw new Error('Access token is not a JWT.');
  }

  const normalizedPayload = payload.replace(/-/g, '+').replace(/_/g, '/');
  const decodedPayload = Buffer.from(normalizedPayload, 'base64').toString('utf8');
  return JSON.parse(decodedPayload);
}

function summarizeAccessToken(tokenResponse) {
  if (!tokenResponse || !tokenResponse.token) {
    throw new Error('Failed to acquire Azure OpenAI access token.');
  }

  const claims = decodeJwtPayload(tokenResponse.token);

  return {
    audience: claims.aud,
    issuer: claims.iss,
    tenantId: claims.tid,
    clientId: claims.appid || claims.azp,
    objectId: claims.oid,
    subject: claims.sub,
    issuedAt: claims.iat ? new Date(claims.iat * 1000).toISOString() : undefined,
    expiresAt: claims.exp ? new Date(claims.exp * 1000).toISOString() : undefined,
    tokenType: 'Bearer',
  };
}

async function generateCompletion(cleanPrompt) {
  const token = await credential.getToken(AZURE_OPENAI_SCOPE);
  if (!token || !token.token) {
    throw new Error('Failed to acquire Azure OpenAI access token.');
  }

  const response = await fetch(
    buildAzureOpenAIUrl(AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_DEPLOYMENT, AZURE_OPENAI_API_VERSION),
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: cleanPrompt },
        ],
      }),
    }
  );

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = payload.error?.message || response.statusText;
    throw new Error(`Azure OpenAI request failed (${response.status}): ${message}`);
  }

  return payload.choices?.[0]?.message?.content || '';
}

// API endpoint to generate content
app.post('/api/generate', async (req, res) => {
  const startTime = Date.now();
  try {
    const { prompt } = req.body;
    const cleanPrompt = formatPrompt(prompt);

    console.log(`Sending prompt to Azure OpenAI deployment: ${AZURE_OPENAI_DEPLOYMENT}`);
    const text = await generateCompletion(cleanPrompt);

    const durationMs = Date.now() - startTime;

    // Return response along with MLOps tracking metadata
    res.json({
      text,
      metadata: {
        deployment: AZURE_OPENAI_DEPLOYMENT,
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

app.get('/api/azure-identity', async (req, res) => {
  try {
    const token = await credential.getToken(AZURE_OPENAI_SCOPE);

    res.json({
      identity: summarizeAccessToken(token),
      service: {
        scope: AZURE_OPENAI_SCOPE,
        endpointConfigured: Boolean(AZURE_OPENAI_ENDPOINT),
        deployment: AZURE_OPENAI_DEPLOYMENT,
        apiVersion: AZURE_OPENAI_API_VERSION,
      },
      proof: 'This pod acquired an Azure AD access token for Azure Cognitive Services without an API key.',
    });
  } catch (err) {
    console.error('Azure identity proof failed:', err);
    res.status(500).json({
      error: 'Failed to acquire Azure identity proof',
      details: err.message,
    });
  }
});

// Expose formatting function and loader for testing
module.exports = {
  app,
  formatPrompt,
  loadSystemPrompt,
  buildAzureOpenAIUrl,
  decodeJwtPayload,
  summarizeAccessToken,
};

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`LLM service listening on port ${PORT}`);
  });
}
