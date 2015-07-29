debug = require('debug')('spec:it:sphere-product-discount-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
{ProductDiscountImport} = require '../../lib'
Config = require '../../config'
Promise = require 'bluebird'
{ExtendedLogger} = require 'sphere-node-utils'
package_json = require '../../package.json'

cleanup = (logger, client) ->
  debug "Deleting old product discounts..."
  client.productDiscounts.all().fetch()
  .then (result) ->
    Promise.all _.map result.body.results, (e) ->
      client.productDiscounts.byId(e.id).delete(e.version)
  .then (results) ->
    debug "#{_.size results} deleted."
    Promise.resolve()

describe 'Product Discount Importer integration tests', ->

  beforeEach (done) ->
    @logger = new ExtendedLogger
      additionalFields:
        project_key: Config.config.project_key
      logConfig:
        name: "#{package_json.name}-#{package_json.version}"
        streams: [
          { level: 'info', stream: process.stdout }
        ]

    @import = new ProductDiscountImport @logger, Config

    @client = @import.client

    @logger.info 'About to setup...'
    cleanup @logger, @client
    .then -> done()
    .catch (err) -> done(_.prettify err)
  , 30000 # 30sec

  afterEach (done) ->
    @logger.info 'About to cleanup...'
    cleanup(@logger, @client)
    .then -> done()
    .catch (err) -> done(_.prettify err)
  , 30000 # 30sec

  it 'should create IN predicate for names', ->
    discounts = [
      { name: { en: 'foo' } }
      { name: { en: 'bar' } }
    ]
    predicate = @import._createProductDiscountFetchByNamePredicate discounts
    expect(predicate).toBe 'name(en in ("foo", "bar"))'

  it 'should create a product discount', (done) ->
    discounts = [
      {
        name: {
          en: 'all 30% off'
        },
        value: {
          type: 'relative',
          permyriad: 3000
        },
        predicate: '1 = 1'
        sortOrder: '0.1',
      }
    ]
    @import.performStream discounts, (res) =>
      expect(res).toBeUndefined()
      @client.productDiscounts.all().fetch()
      .then (res) ->
        expect(_.size res.body.results).toBe 1
        discount = res.body.results[0]
        expect(discount.name.en).toBe 'all 30% off'
        done()
      .catch (err) ->
        done(_.prettify err)
  , 30000

  it 'should not update an unchanged existing product discount', (done) ->
    discounts = [
      {
        name: {
          en: 'all 50% off'
        },
        value: {
          type: 'relative',
          permyriad: 5000
        },
        predicate: '1 = 1'
        sortOrder: '0.2',
      }
    ]
    @import.performStream discounts, (res) =>
      expect(res).toBeUndefined()
      @import.performStream discounts, (res) =>
        expect(res).toBeUndefined()
        @client.productDiscounts.all().fetch()
        .then (res) ->
          expect(_.size res.body.results).toBe 1
          discount = res.body.results[0]
          expect(discount.name.en).toBe 'all 50% off'
          done()
        .catch (err) ->
          done(_.prettify err)
  , 30000

  it 'should update the predicate of an existing product discount', (done) ->
    discounts = [
      {
        name: {
          en: 'all 10% off'
        },
        value: {
          type: 'relative',
          permyriad: 1000
        },
        predicate: '1 = 1'
        sortOrder: '0.3',
      }
    ]
    @import.performStream discounts, (res) =>
      expect(res).toBeUndefined()
      discounts = [
        {
          name: {
            en: 'all 10% off'
          },
          value: {
            type: 'relative',
            permyriad: 1000
          },
          predicate: '2 = 2'
          sortOrder: '0.3',
        }
      ]
      @import.performStream discounts, (res) =>
        expect(res).toBeUndefined()
        @client.productDiscounts.all().fetch()
        .then (res) ->
          expect(_.size res.body.results).toBe 1
          discount = res.body.results[0]
          expect(discount.name.en).toBe 'all 10% off'
          expect(discount.predicate).toBe '2 = 2'
          done()
        .catch (err) ->
          done(_.prettify err.body)
  , 30000