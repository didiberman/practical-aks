const {
  formatPrompt,
  loadSystemPrompt,
  buildAzureOpenAIUrl,
  decodeJwtPayload,
  summarizeAccessToken,
} = require('../index');

function unsignedJwt(payload) {
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.`;
}

describe('MLOps Prompt Validation Tests', () => {
  
  test('should load the system prompt correctly', () => {
    const systemPrompt = loadSystemPrompt();
    expect(systemPrompt).toBeDefined();
    expect(systemPrompt.length).toBeGreaterThan(0);
    expect(systemPrompt).toContain('MLOps');
    expect(systemPrompt).toContain('Azure');
  });

  test('should successfully format valid user prompts', () => {
    const rawInput = '   explain how to configure workload identity   ';
    const formatted = formatPrompt(rawInput);
    expect(formatted).toBe('explain how to configure workload identity');
  });

  test('should throw an error on empty prompts', () => {
    expect(() => formatPrompt('')).toThrow('Input prompt cannot be empty.');
    expect(() => formatPrompt('   ')).toThrow('Input prompt cannot be empty.');
    expect(() => formatPrompt(null)).toThrow('Input prompt cannot be empty.');
  });

  test('should build Azure OpenAI chat completions URL', () => {
    const url = buildAzureOpenAIUrl(
      'https://example-openai.openai.azure.com/',
      'gpt-4o-mini',
      '2024-10-21'
    );
    expect(url).toBe('https://example-openai.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21');
  });

  test('should decode JWT payload claims for identity proof', () => {
    const token = unsignedJwt({
      aud: 'https://cognitiveservices.azure.com',
      tid: 'tenant-id',
      appid: 'client-id',
      oid: 'object-id',
    });

    expect(decodeJwtPayload(token)).toMatchObject({
      aud: 'https://cognitiveservices.azure.com',
      tid: 'tenant-id',
      appid: 'client-id',
      oid: 'object-id',
    });
  });

  test('should summarize access token without exposing the raw token', () => {
    const token = unsignedJwt({
      aud: 'https://cognitiveservices.azure.com',
      iss: 'https://sts.windows.net/tenant-id/',
      tid: 'tenant-id',
      appid: 'client-id',
      oid: 'object-id',
      sub: 'subject-id',
      iat: 1710000000,
      exp: 1710003600,
    });

    const summary = summarizeAccessToken({ token });

    expect(summary).toEqual({
      audience: 'https://cognitiveservices.azure.com',
      issuer: 'https://sts.windows.net/tenant-id/',
      tenantId: 'tenant-id',
      clientId: 'client-id',
      objectId: 'object-id',
      subject: 'subject-id',
      issuedAt: '2024-03-09T16:00:00.000Z',
      expiresAt: '2024-03-09T17:00:00.000Z',
      tokenType: 'Bearer',
    });
    expect(summary.token).toBeUndefined();
  });
});
