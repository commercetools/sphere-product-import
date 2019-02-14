var ProductDiscountImport, Promise, Repeater, SphereClient, _, debug, slugify;

debug = require('debug')('sphere-discount-import');

_ = require('underscore');

_.mixin(require('underscore-mixins'));

Promise = require('bluebird');

slugify = require('underscore.string/slugify');

SphereClient = require('sphere-node-sdk').SphereClient;

Repeater = require('sphere-node-utils').Repeater;

ProductDiscountImport = (function() {
  function ProductDiscountImport(logger, options) {
    this.logger = logger;
    if (options == null) {
      options = {};
    }
    this.client = new SphereClient(options.clientConfig);
    this.language = 'en';
    this._resetSummary();
  }

  ProductDiscountImport.prototype._resetSummary = function() {
    return this._summary = {
      created: 0,
      updated: 0,
      unChanged: 0
    };
  };

  ProductDiscountImport.prototype.summaryReport = function() {
    var message;
    if (this._summary.updated === 0) {
      message = 'Summary: nothing to update';
    } else {
      message = "Summary: there were " + this._summary.updated + " update(s) and " + this._summary.created + " creation(s) of product discount.";
    }
    return message;
  };

  ProductDiscountImport.prototype.performStream = function(chunk, cb) {
    return this._processBatches(chunk).then(function() {
      return cb();
    })["catch"](function(err) {
      return cb(err.body);
    });
  };

  ProductDiscountImport.prototype._createProductDiscountFetchByNamePredicate = function(discounts) {
    var names;
    names = _.map(discounts, (function(_this) {
      return function(d) {
        return "\"" + d.name[_this.language] + "\"";
      };
    })(this));
    return "name(" + this.language + " in (" + (names.join(', ')) + "))";
  };

  ProductDiscountImport.prototype._processBatches = function(discounts) {
    var batchedList;
    batchedList = _.batchList(discounts, 30);
    return Promise.map(batchedList, (function(_this) {
      return function(discountsToProcess) {
        var predicate;
        predicate = _this._createProductDiscountFetchByNamePredicate(discountsToProcess);
        return _this.client.productDiscounts.where(predicate).all().fetch().then(function(results) {
          var queriedEntries;
          debug("Fetched product discounts: %j", results);
          queriedEntries = results.body.results;
          return _this._createOrUpdate(discountsToProcess, queriedEntries).then(function(results) {
            _.each(results, function(r) {
              switch (r.statusCode) {
                case 200:
                  return _this._summary.updated++;
                case 201:
                  return _this._summary.created++;
                case 304:
                  return _this._summary.unChanged++;
              }
            });
            return Promise.resolve(_this._summary);
          });
        });
      };
    })(this), {
      concurrency: 1
    });
  };

  ProductDiscountImport.prototype._findMatch = function(discount, existingDiscounts) {
    return _.find(existingDiscounts, (function(_this) {
      return function(d) {
        return _.isString(d.name[_this.language]) && d.name[_this.language] === discount.name[_this.language];
      };
    })(this));
  };

  ProductDiscountImport.prototype._createOrUpdate = function(discountsToProcess, existingDiscounts) {
    var posts;
    debug('Product discounts to process: %j', {
      toProcess: discountsToProcess,
      existing: existingDiscounts
    });
    posts = _.map(discountsToProcess, (function(_this) {
      return function(discount) {
        var existingDiscount, payload;
        existingDiscount = _this._findMatch(discount, existingDiscounts);
        if (existingDiscount != null) {
          if (discount.predicate === existingDiscount.predicate) {
            return Promise.resolve({
              statusCode: 304
            });
          } else {
            payload = {
              version: existingDiscount.version,
              actions: [
                {
                  action: 'changePredicate',
                  predicate: discount.predicate
                }
              ]
            };
            return _this.client.productDiscounts.byId(existingDiscount.id).update(payload);
          }
        } else {
          return _this.client.productDiscounts.create(discount);
        }
      };
    })(this));
    debug('About to send %s requests', _.size(posts));
    return Promise.all(posts);
  };

  return ProductDiscountImport;

})();

module.exports = ProductDiscountImport;
