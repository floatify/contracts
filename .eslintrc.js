module.exports = {
  root: true,

  parserOptions: {
    parser: 'babel-eslint',
    sourceType: 'module'
  },

  env: {
    browser: true,
  },

  extends: [
    'airbnb-base',
  ],

  plugins: [
    'chai-friendly'
  ],

  globals: {
    'web3': true,
    'artifacts': true,
    'contract': true,
    'it': true,
    'before': true,
    'beforeEach': true,
    'afterEach': true,
    'describe': true,
  },

  // add your custom rules here
  rules: {
    'no-param-reassign': 'off',

    'import/first': 'off',
    'import/named': 'error',
    'import/namespace': 'error',
    'import/default': 'error',
    'import/export': 'error',
    'import/extensions': 'off',
    'import/no-unresolved': 'off',
    'import/no-extraneous-dependencies': 'off',
    'import/prefer-default-export': 'off',
    'prefer-promise-reject-errors': 'off',

    'max-len': [1, 120, 2],

    // to use eslint-plugin-chai-friendly
    // source: https://www.npmjs.com/package/eslint-plugin-chai-friendly
    'no-unused-expressions': 0,
    'chai-friendly/no-unused-expressions': 2,

    'max-len': ["error", {
      "code": 120,
      "ignoreUrls": true,
      "ignoreRegExpLiterals": true,
    }],
  }
}
