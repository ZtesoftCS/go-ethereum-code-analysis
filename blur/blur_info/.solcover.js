module.exports = {
  port: 8555,
  configureYulOptimizer: true,
  compileCommand: './node_modules/.bin/hardhat compile',
  testCommand: './node_modules/.bin/hardhat test',
  skipFiles: ['mocks', 'interfaces'],
  providerOptions: {
    mnemonic: process.env.MNEMONIC,
  },
};
