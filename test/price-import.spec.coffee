_ = require 'underscore'
_.mixin require 'underscore-mixins'
{PriceImport} = require '../lib'
ClientConfig = require '../config'
Promise = require 'bluebird'
jasmine = require 'jasmine-node'
cuid = require 'cuid'

mockPrice = (options = {}) ->
  id: cuid()
  value:
    currencyCode: options.currency || "EUR",
    centAmount: options.amount || 4200
  country: options.country || "DE"

addPriceAction =
  action: 'addPrice'
  variantId: 'variantId'
  price: mockPrice()

changePriceAction = (priceId = cuid()) ->
  action: 'changePrice'
  priceId: priceId

priceActionDeprecated = (action = "addPrice", variantId, price) ->
  if !action
    throw new Error 'no-action'
  if !variantId
    throw new Error 'no-variant-id'
  if !price
    throw new Error 'no-price'
  {
    action: action
    variantId: variantId,
    price: price
  }

removePriceAction = (priceId = cuid()) ->
  action: 'removePrice'
  priceId: priceId

priceActions = [ addPriceAction, removePriceAction() ]

describe 'PriceImport', ->

  beforeEach ->

    Config =
      clientConfig: ClientConfig
      errorLimit: 0

    @import = new PriceImport null, Config

  it 'should initialize', ->
    expect(@import).toBeDefined()

  describe '::_wrapPricesIntoProducts', ->

    it 'should wrap a product around a single price', ->
      products = [
        {
          id: 'id123'
          masterVariant:
            sku: '123'
        }
      ]
      prices = [
        {
          sku: '123'
          prices: [
            {
              value:
                currencyCode: 'EUR'
                centAmount: 799
              country: 'DE'
              validFrom: '2000-01-01T00:00:00'
              validTo: '2099-12-31T23:59:59'
            }
          ]
        }
      ]

      modifiedProducts = @import._wrapPricesIntoProducts prices, products
      expect(_.size modifiedProducts).toBe 1
      product = modifiedProducts[0]
      price = prices[0].prices[0]
      expect(product.masterVariant.sku).toBe prices[0].sku
      expect(_.size product.masterVariant.prices).toBe 1
      expect(product.masterVariant.prices[0].sku).toBeUndefined()
      expect(product.masterVariant.prices[0].value).toEqual price.value
      expect(product.masterVariant.prices[0].validFrom).toEqual price.validFrom
      expect(product.masterVariant.prices[0].validTo).toEqual price.validTo
      expect(product.masterVariant.prices[0].country).toEqual price.country
      # channel
      # customerGroup

    it 'should add all prices to the product', ->
      products = [
        {
          id: 'id123'
          masterVariant:
            sku: '123'
        }
      ]
      prices = [
        {
          sku: '123'
          prices: [
            {
              value:
                currencyCode: 'EUR'
                centAmount: 799
              country: 'DE'
              validFrom: '2000-01-01T00:00:00'
              validTo: '2099-12-31T23:59:59'
            }
            {
              value:
                currencyCode: 'USD'
                centAmount: 1099
              country: 'US'
              validFrom: '2000-01-01T00:00:00'
              validTo: '2099-12-31T23:59:59'
            }
          ]
        }
      ]

      modifiedProducts = @import._wrapPricesIntoProducts prices, products
      expect(_.size modifiedProducts).toBe 1
      expect(_.size modifiedProducts[0].masterVariant.prices).toBe 2

  describe '_filterPriceActions', ->

    it 'should filter out price deletion actions', (done) ->

      filteredActions = @import._filterPriceActions(priceActions)

      actual = filteredActions
      expected = [ addPriceAction ]

      expect(actual).toEqual(expected)
      done()

  describe '_createOrUpdate', ->

    updateStub =
      update: (actions) ->
        new Promise (resolve) -> resolve()

    beforeEach ->

      @priceDe = mockPrice({ country: "DE" })
      @priceUs = mockPrice({ country: "US" })
      @sku = cuid()
      @variantId = cuid()

      spyOn(@import.client.products, 'byId').andReturn(updateStub)
      spyOn(updateStub, 'update')

    it 'should call remove actions', (done) ->

      existingProduct =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceDe, @priceUs ]

      productsToProcess =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceDe ]

      @import._createOrUpdate([ productsToProcess ], [ existingProduct ])
      .then =>

        actual = updateStub.update.mostRecentCall.args[0]
        expected =
          version: productsToProcess.version
          actions: [
            priceActionDeprecated(
              "removePrice"
              @variantId,
              _.omit(@priceUs, 'id')
            )
          ]

        expect(actual).toEqual(expected)
      .catch (err) -> done(err)
      .finally -> done()

    it "should not call remove actions
    if preventRemoveActions flag is set to true", (done) ->

      @import.preventRemoveActions = true

      existingProduct =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceDe, @priceUs ]

      productsToProcess =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceDe ]

      @import._createOrUpdate([ productsToProcess ], [ existingProduct ])
      .then ->

        actual = updateStub.update.mostRecentCall.args[0]
        expected =
          actions: []
          version: productsToProcess.version

        expect(actual).toEqual(expected)
      .catch (err) -> done(err)
      .finally =>
        @import.preventRemoveActions = false
        done()

    it 'should generate add actions', (done) ->

      productsToProcess =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceDe, @priceUs ]

      existingProduct =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceDe ]

      @import._createOrUpdate([ productsToProcess ], [ existingProduct ])
      .then =>

        actual = updateStub.update.mostRecentCall.args[0]
        expected =
          version: productsToProcess.version
          actions: [
            priceActionDeprecated(
              "addPrice",
              @variantId,
              _.omit(@priceUs, 'id')
            )
          ]

        expect(actual).toEqual(expected)
      .catch (err) -> done(err)
      .finally -> done()

    it 'should generate change actions', (done) ->

      productsToProcess =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceDe ]

      changedPrice = _.deepClone(@priceDe)
      changedPrice.value.centAmount = 0

      existingProduct =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ changedPrice ]

      @import._createOrUpdate([ productsToProcess ], [ existingProduct ])
      .then =>

        actual = updateStub.update.mostRecentCall.args[0]
        expected =
          version: productsToProcess.version
          actions: [
            priceActionDeprecated(
              "changePrice",
              @variantId,
              _.omit(changedPrice, 'id')
            )
          ]

        expect(actual).toEqual(expected)
      .catch (err) -> done(err)
      .finally -> done()

  describe 'publish updates', ->

    updateStub =
      update: (actions) ->
        new Promise (resolve) -> resolve()

    beforeEach ->

      @priceDe = mockPrice({ country: "DE" })
      @priceUs = mockPrice({ country: "US" })
      @sku = cuid()
      @variantId = cuid()

      spyOn(@import.client.products, 'byId').andReturn(updateStub)
      spyOn(updateStub, 'update')

    it 'should add publish action to update actions', (done) ->
      existingProduct =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceUs ]
        hasStagedChanges: false
        published: true

      productToProcess =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceUs, @priceDe ]
        hasStagedChanges: false
        published: true

      @import.publishingStrategy = 'notStagedAndPublishedOnly'
      @import._createOrUpdate([productToProcess], [existingProduct])
      .then =>
        actual = updateStub.update.mostRecentCall.args[0]
        expected =
          version: productToProcess.version
          actions: [
            priceActionDeprecated(
              "addPrice",
              @variantId,
              _.omit(@priceDe, 'id')
            ),
            { action: 'publish' }
          ]
        expect(actual).toEqual(expected)
      .catch (err) -> done(err)
      .finally -> done()

    it 'should not add publish action to update actions when disabled', (done) ->
      existingProduct =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceUs ]
        hasStagedChanges: false
        published: true

      productToProcess =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceUs, @priceDe ]
        hasStagedChanges: false
        published: true

      @import.publishingStrategy = false
      @import._createOrUpdate([productToProcess], [existingProduct])
      .then =>
        actual = updateStub.update.mostRecentCall.args[0]
        expected =
          version: productToProcess.version
          actions: [
            priceActionDeprecated(
              "addPrice",
              @variantId,
              _.omit(@priceDe, 'id')
            )
          ]
        expect(actual).toEqual(expected)
      .catch (err) -> done(err)
      .finally -> done()

    it 'should not add publish action to update actions when product not published
       and has staged changes', (done) ->
      existingProduct =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceUs ]
        hasStagedChanges: true
        published: false

      productToProcess =
        version: 1
        masterVariant:
          sku: @sku
          id: @variantId
          prices: [ @priceUs, @priceDe ]
        hasStagedChanges: false
        published: true

      @import.publishingStrategy = 'notStagedAndPublishedOnly'
      @import._createOrUpdate([productToProcess], [existingProduct])
      .then =>
        actual = updateStub.update.mostRecentCall.args[0]
        expected =
          version: productToProcess.version
          actions: [
            priceActionDeprecated(
              "addPrice",
              @variantId,
              _.omit(@priceDe, 'id')
            )
          ]
        expect(actual).toEqual(expected)
      .catch (err) -> done(err)
      .finally -> done()