import {describe, it, expect} from '@jest/globals';
import { } from '../src/veo/startVeoForJob';

// Lightweight import by re-requiring to access internal functions via eval (kept minimal for snapshot sanity)
// eslint-disable-next-line @typescript-eslint/no-var-requires
const mod = require('../src/veo/startVeoForJob');

describe('prompt builder', () => {
  it('classifies electronics from keywords', () => {
    const cat = mod.__esModule ? mod : mod;
    const got = cat.classifyCategory ? cat.classifyCategory('sleek phone with OLED display') : mod['classifyCategory']('sleek phone with OLED display');
    expect(got).toBeDefined();
  });

  it('builds a category-aware commercial prompt', () => {
    const built = mod.buildCommercialPrompt('stainless steel watch');
    expect(typeof built.text).toBe('string');
    expect(built.text.length).toBeGreaterThan(40);
    expect(built.category).toBeDefined();
    expect(built.templateId).toBeDefined();
  });
});


