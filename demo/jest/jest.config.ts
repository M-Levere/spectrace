import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['**/__tests__/**/*.test.ts'],
  reporters: [
    'default',
    ['jest-junit', { outputDirectory: 'test-results', outputName: 'junit.xml' }],
    ['<rootDir>/node_modules/jest-json-reporter', { outputFile: 'test-results/results.json' }],
  ],
  testTimeout: 5000,
};

export default config;
