_ = require 'underscore'
_.mixin require 'underscore-mixins'
{ProductExport} = require '../lib'
Config = require '../config'
Promise = require 'bluebird'

describe 'ProductExport', ->

  beforeEach ->
    @export = new ProductExport null, Config

  it 'should initialize', ->
    expect(@export).toBeDefined()
    expect(@export.client).toBeDefined()
    expect(@export.client.constructor.name).toBe 'SphereClient'

  describe '::processStream', ->

    it 'should execute callback after finished processing batches', (done) ->
      spyOn(@export.client._rest, 'GET').andCallFake (endpoint, callback) ->
        callback(null, {statusCode: 200}, {total: 1, results: [{foo: 'bar'}]})
      @export.processStream (payload) ->
        expect(payload.body.results).toEqual [{foo: 'bar'}]
        Promise.resolve()
      .then -> done()
      .catch done
