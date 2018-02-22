var PriceImport, ProductImport, ProductSync, Promise, Repeater, SphereClient, _, debug, ref, slugify,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty;

debug = require('debug')('sphere-price-import');

_ = require('underscore');

_.mixin(require('underscore-mixins'));

Promise = require('bluebird');

slugify = require('underscore.string/slugify');

ref = require('sphere-node-sdk'), SphereClient = ref.SphereClient, ProductSync = ref.ProductSync;

Repeater = require('sphere-node-utils').Repeater;

ProductImport = require('./product-import');

PriceImport = (function(superClass) {
  extend(PriceImport, superClass);

  function PriceImport(logger, options) {
    this.logger = logger;
    if (options == null) {
      options = {};
    }
    this._resolvePriceReferences = bind(this._resolvePriceReferences, this);
    this._preparePrice = bind(this._preparePrice, this);
    this._preparePrices = bind(this._preparePrices, this);
    this._handleFulfilledResponse = bind(this._handleFulfilledResponse, this);
    PriceImport.__super__.constructor.call(this, this.logger, options);
    this.batchSize = options.batchSize || 30;
    this.sync.config([
      {
        type: 'prices',
        group: 'white'
      }
    ].concat(['base', 'references', 'attributes', 'images', 'variants', 'metaAttributes'].map(function(type) {
      return {
        type: type,
        group: 'black'
      };
    })));
    this.repeater = new Repeater;
    this.preventRemoveActions = options.preventRemoveActions || false;
  }

  PriceImport.prototype._resetSummary = function() {
    return this._summary = {
      unknownSKUCount: 0,
      duplicatedSKUs: 0,
      variantWithoutPriceUpdates: 0,
      updated: 0,
      failed: 0
    };
  };

  PriceImport.prototype.summaryReport = function() {
    return ("Summary: there were " + this._summary.updated + " price update(s). ") + ("(unknown skus: " + this._summary.unknownSKUCount + ", duplicate skus: " + this._summary.duplicatedSKUs + ", variants without price updates: " + this._summary.variantWithoutPriceUpdates + ")");
  };

  PriceImport.prototype._processBatches = function(prices) {
    var batchedList;
    batchedList = _.batchList(prices, this.batchSize);
    return Promise.map(batchedList, (function(_this) {
      return function(pricesToProcess) {
        var predicate, skus;
        skus = _.map(pricesToProcess, function(p) {
          return p.sku;
        });
        predicate = _this._createProductFetchBySkuQueryPredicate(skus);
        return _this.client.productProjections.where(predicate).staged(true).all().fetch().then(function(results) {
          var queriedEntries;
          queriedEntries = results.body.results;
          return _this._preparePrices(pricesToProcess).then(function(preparedPrices) {
            var wrappedProducts;
            wrappedProducts = _this._wrapPricesIntoProducts(preparedPrices, queriedEntries);
            if (_this.logger) {
              _this.logger.info("Wrapped " + (_.size(preparedPrices)) + " price(s) into " + (_.size(wrappedProducts)) + " existing product(s).");
            }
            return _this._createOrUpdate(wrappedProducts, queriedEntries).then(function(results) {
              _.each(results, function(r) {
                return _this._handleProcessResponse(r);
              });
              return Promise.resolve(_this._summary);
            });
          });
        });
      };
    })(this), {
      concurrency: 1
    });
  };

  PriceImport.prototype._handleFulfilledResponse = function(r) {
    switch (r.value().statusCode) {
      case 201:
        return this._summary.created++;
      case 200:
        return this._summary.updated++;
      case 404:
        return this._summary.unknownSKUCount++;
      case 304:
        return this._summary.variantWithoutPriceUpdates++;
    }
  };

  PriceImport.prototype._preparePrices = function(pricesToProcess) {
    return Promise.map(pricesToProcess, (function(_this) {
      return function(priceToProcess) {
        return _this._preparePrice(priceToProcess);
      };
    })(this), {
      concurrency: 1
    });
  };

  PriceImport.prototype._preparePrice = function(priceToProcess) {
    var resolvedPrices;
    resolvedPrices = [];
    return Promise.map(priceToProcess.prices, (function(_this) {
      return function(price) {
        return _this._resolvePriceReferences(price).then(function(resolved) {
          return resolvedPrices.push(resolved);
        });
      };
    })(this), {
      concurrency: 1
    }).then(function() {
      priceToProcess.prices = resolvedPrices;
      return Promise.resolve(priceToProcess);
    });
  };

  PriceImport.prototype._resolvePriceReferences = function(price) {
    var ref1, ref2;
    return Promise.all([this._resolveReference(this.client.customerGroups, 'customerGroup', price.customerGroup, "name=\"" + ((ref1 = price.customerGroup) != null ? ref1.id : void 0) + "\""), this._resolveReference(this.client.channels, 'channel', price.channel, "key=\"" + ((ref2 = price.channel) != null ? ref2.id : void 0) + "\"")]).spread(function(customerGroupId, channelId) {
      if (customerGroupId) {
        price.customerGroup = {
          id: customerGroupId,
          typeId: 'customer-group'
        };
      }
      if (channelId) {
        price.channel = {
          id: channelId,
          typeId: 'channel'
        };
      }
      return Promise.resolve(price);
    });
  };

  PriceImport.prototype._createOrUpdate = function(productsToProcess, existingProducts) {
    var posts;
    debug('Products to process: %j', {
      toProcess: productsToProcess,
      existing: existingProducts
    });
    posts = _.map(productsToProcess, (function(_this) {
      return function(prodToProcess) {
        var existingProduct, synced, updateTask;
        existingProduct = _this._isExistingEntry(prodToProcess, existingProducts);
        if (existingProduct != null) {
          synced = _this.sync.buildActions(prodToProcess, existingProduct);
          if (synced.shouldUpdate()) {
            updateTask = function(payload) {
              return _this.client.products.byId(synced.getUpdateId()).update(payload);
            };
            return _this.repeater.execute(function() {
              var payload;
              payload = synced.getUpdatePayload();
              if (_this.preventRemoveActions) {
                payload.actions = _this._filterPriceActions(payload.actions);
              }
              if (_this.publishingStrategy && _this.commonUtils.canBePublished(existingProduct, _this.publishingStrategy)) {
                payload.actions.push({
                  action: 'publish'
                });
              }
              return updateTask(payload);
            }, function(e) {
              var newTask;
              if (e.statusCode === 409) {
                debug('retrying to update %s because of 409', synced.getUpdateId());
                newTask = function() {
                  return _this.client.productProjections.staged(true).byId(synced.getUpdateId()).fetch().then(function(result) {
                    var newPayload;
                    newPayload = _.extend({}, synced.getUpdatePayload(), {
                      version: result.body.version
                    });
                    return updateTask(newPayload);
                  });
                };
                return Promise.resolve(newTask);
              } else {
                return Promise.reject(e);
              }
            });
          } else {
            return Promise.resolve({
              statusCode: 304
            });
          }
        } else {
          _this._summary.unknownSKUCount++;
          return Promise.resolve({
            statusCode: 404
          });
        }
      };
    })(this));
    debug('About to send %s requests', _.size(posts));
    return Promise.settle(posts);
  };


  /**
   * filters out remove actions
   * so no prices get deleted
   */

  PriceImport.prototype._filterPriceActions = function(actions) {
    return _.filter(actions, function(action) {
      return action.action !== "removePrice";
    });
  };

  PriceImport.prototype._wrapPricesIntoProducts = function(prices, products) {
    var productsWithPrices, sku2index;
    sku2index = {};
    _.each(prices, (function(_this) {
      return function(p, index) {
        if (!_.has(sku2index, p.sku)) {
          return sku2index[p.sku] = index;
        } else {
          _this.logger.warn("Duplicate SKU found - '" + p.sku + "' - ignoring!");
          return _this._summary.duplicatedSKUs++;
        }
      };
    })(this));
    productsWithPrices = _.map(products, (function(_this) {
      return function(p) {
        var product;
        product = _.deepClone(p);
        _this._wrapPricesIntoVariant(product.masterVariant, prices, sku2index);
        _.each(product.variants, function(v) {
          return _this._wrapPricesIntoVariant(v, prices, sku2index);
        });
        return product;
      };
    })(this));
    this._summary.unknownSKUCount += Object.keys(sku2index).length;
    return productsWithPrices;
  };

  PriceImport.prototype._wrapPricesIntoVariant = function(variant, prices, sku2index) {
    var index;
    if (_.has(sku2index, variant.sku)) {
      index = sku2index[variant.sku];
      variant.prices = _.deepClone(prices[index].prices);
      return delete sku2index[variant.sku];
    } else {
      return this._summary.variantWithoutPriceUpdates++;
    }
  };

  return PriceImport;

})(ProductImport);

module.exports = PriceImport;
