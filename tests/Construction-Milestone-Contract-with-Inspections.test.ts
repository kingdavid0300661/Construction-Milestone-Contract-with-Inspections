const { assert } = require('chai');
const { Client, Provider, ProviderRegistry, Result } = require('@blockstack/clarity');

import { describe, it, before } from 'mocha';

describe('construction-milestone-contract', () => {
  let client: Client;
  let provider: Provider;

  before(async () => {
    provider = await ProviderRegistry.createProvider();
    client = new Client('construction-milestone-contract', 'construction-milestone-contract-tests');
  });

  describe('milestone management', function () {
    it('should add milestone successfully', async function () {
      const result = await client.executeContract('add-milestone', ['Foundation Work', 1000, 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7', 100]);
      assert.equal(result.success, true);
    });

    it('should fail when non-owner adds milestone', async function () {
      const result: Result = await client.executeContract('add-milestone', ['Roofing', 500, 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7', 100], 'SP3GWX3NE58KXHESRYE4DYQ1S31PQJTCRXB3PE9SB');
      assert.equal(result.success, false);
    });
  });
});