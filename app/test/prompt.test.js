const { formatPrompt, loadSystemPrompt } = require('../index');

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
});
