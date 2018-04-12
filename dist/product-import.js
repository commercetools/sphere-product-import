var CommonUtils, EnsureDefaultAttributes, EnumValidator, ProductImport, ProductSync, Promise, Reassignment, Repeater, SphereClient, UnknownAttributesFilter, _, debug, fs, path, ref1, serializeError, slugify, util,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

debug = require('debug')('sphere-product-import');

_ = require('underscore');

_.mixin(require('underscore-mixins'));

Promise = require('bluebird');

slugify = require('underscore.string/slugify');

ref1 = require('sphere-node-sdk'), SphereClient = ref1.SphereClient, ProductSync = ref1.ProductSync;

Repeater = require('sphere-node-utils').Repeater;

fs = require('fs-extra');

path = require('path');

serializeError = require('serialize-error');

EnumValidator = require('./enum-validator');

UnknownAttributesFilter = require('./unknown-attributes-filter');

CommonUtils = require('./common-utils');

EnsureDefaultAttributes = require('./ensure-default-attributes');

util = require('util');

Reassignment = require('commercetools-node-variant-reassignment')["default"];

ProductImport = (function() {
  function ProductImport(logger1, options) {
    this.logger = logger1;
    if (options == null) {
      options = {};
    }
    this._fetchAndResolveCustomReferences = bind(this._fetchAndResolveCustomReferences, this);
    this._updateProductSlug = bind(this._updateProductSlug, this);
    this._ensureDefaults = bind(this._ensureDefaults, this);
    this._fetchSameForAllAttributesOfProductType = bind(this._fetchSameForAllAttributesOfProductType, this);
    this._updateProductType = bind(this._updateProductType, this);
    this._validateEnums = bind(this._validateEnums, this);
    this._ensureProductTypeInMemory = bind(this._ensureProductTypeInMemory, this);
    this._ensureDefaultAttributesInProducts = bind(this._ensureDefaultAttributesInProducts, this);
    this._ensureProductTypesInMemory = bind(this._ensureProductTypesInMemory, this);
    this._filterUniqueUpdateActions = bind(this._filterUniqueUpdateActions, this);
    this._filterAttributes = bind(this._filterAttributes, this);
    this._handleFulfilledResponse = bind(this._handleFulfilledResponse, this);
    this._handleProcessResponse = bind(this._handleProcessResponse, this);
    this._errorLogger = bind(this._errorLogger, this);
    this._getExistingProductsForSkus = bind(this._getExistingProductsForSkus, this);
    this._configErrorHandling = bind(this._configErrorHandling, this);
    this._configureSync = bind(this._configureSync, this);
    this.sync = new ProductSync;
    if (options.blackList && ProductSync.actionGroups) {
      this.sync.config(this._configureSync(options.blackList));
    }
    this.errorCallback = options.errorCallback || this._errorLogger;
    this.ensureEnums = options.ensureEnums || false;
    this.filterUnknownAttributes = options.filterUnknownAttributes || false;
    this.ignoreSlugUpdates = options.ignoreSlugUpdates || false;
    this.batchSize = options.batchSize || 30;
    this.failOnDuplicateAttr = options.failOnDuplicateAttr || false;
    this.logOnDuplicateAttr = options.logOnDuplicateAttr != null ? options.logOnDuplicateAttr : true;
    this.client = new SphereClient(options.clientConfig);
    this.enumValidator = new EnumValidator(this.logger);
    this.unknownAttributesFilter = new UnknownAttributesFilter(this.logger);
    this.commonUtils = new CommonUtils(this.logger);
    this.filterActions = _.isFunction(options.filterActions) ? options.filterActions : _.isArray(options.filterActions) ? function(action) {
      return !_.contains(options.filterActions, action.action);
    } : function(action) {
      return true;
    };
    this.urlLimit = 8192;
    if (options.defaultAttributes) {
      this.defaultAttributesService = new EnsureDefaultAttributes(this.logger, options.defaultAttributes);
    }
    this.publishingStrategy = options.publishingStrategy || false;
    this.variantReassignmentOptions = options.variantReassignmentOptions || {};
    this._configErrorHandling(options);
    this._resetCache();
    this._resetSummary();
    debug("Product Importer initialized with config -> errorDir: " + this.errorDir + ", errorLimit: " + this.errorLimit + ", blacklist actions: " + options.blackList + ", ensureEnums: " + this.ensureEnums);
  }

  ProductImport.prototype._configureSync = function(blackList) {
    this._validateSyncConfig(blackList);
    debug("Product sync config validated");
    return _.difference(ProductSync.actionGroups, blackList).map(function(type) {
      return {
        type: type,
        group: 'white'
      };
    }).concat(blackList.map(function(type) {
      return {
        type: type,
        group: 'black'
      };
    }));
  };

  ProductImport.prototype._validateSyncConfig = function(blackList) {
    var actionGroup, i, len, results1;
    results1 = [];
    for (i = 0, len = blackList.length; i < len; i++) {
      actionGroup = blackList[i];
      if (!_.contains(ProductSync.actionGroups, actionGroup)) {
        throw "invalid product sync action group: " + actionGroup;
      } else {
        results1.push(void 0);
      }
    }
    return results1;
  };

  ProductImport.prototype._configErrorHandling = function(options) {
    if (options.errorDir) {
      this.errorDir = options.errorDir;
    } else {
      this.errorDir = path.join(__dirname, '../errors');
    }
    fs.emptyDirSync(this.errorDir);
    if (options.errorLimit) {
      return this.errorLimit = options.errorLimit;
    } else {
      return this.errorLimit = 30;
    }
  };

  ProductImport.prototype._resetCache = function() {
    return this._cache = {
      productType: {},
      categories: {},
      taxCategory: {}
    };
  };

  ProductImport.prototype._resetSummary = function() {
    this._summary = {
      productsWithMissingSKU: 0,
      created: 0,
      updated: 0,
      failed: 0,
      productTypeUpdated: 0,
      errorDir: this.errorDir
    };
    if (this.filterUnknownAttributes) {
      this._summary.unknownAttributeNames = [];
    }
    if (this.variantReassignmentOptions.enabled) {
      return this._summary.variantReassignment = null;
    }
  };

  ProductImport.prototype.summaryReport = function(filename) {
    var message, report;
    message = ("Summary: there were " + (this._summary.created + this._summary.updated) + " imported products ") + ("(" + this._summary.created + " were new and " + this._summary.updated + " were updates).");
    if (this._summary.productsWithMissingSKU > 0) {
      message += "\nFound " + this._summary.productsWithMissingSKU + " product(s) which do not have SKU and won't be imported.";
      if (filename) {
        message += " '" + filename + "'";
      }
    }
    if (this._summary.failed > 0) {
      message += "\n " + this._summary.failed + " product imports failed. Error reports stored at: " + this.errorDir;
    }
    report = {
      reportMessage: message,
      detailedSummary: this._summary
    };
    return report;
  };

  ProductImport.prototype.performStream = function(chunk, cb) {
    return this._processBatches(chunk).then(function() {
      return cb();
    });
  };

  ProductImport.prototype._processBatches = function(products) {
    var batchedList;
    batchedList = _.batchList(products, this.batchSize);
    return Promise.map(batchedList, (function(_this) {
      return function(productsToProcess) {
        debug('Ensuring existence of product type in memory.');
        return _this._ensureProductTypesInMemory(productsToProcess).then(function() {
          var enumUpdateActions, uniqueEnumUpdateActions;
          if (_this.ensureEnums) {
            debug('Ensuring existence of enum keys in product type.');
            enumUpdateActions = _this._validateEnums(productsToProcess);
            uniqueEnumUpdateActions = _this._filterUniqueUpdateActions(enumUpdateActions);
            return _this._updateProductType(uniqueEnumUpdateActions);
          }
        }).then(function() {
          var filteredProductsLength, originalLength, skus;
          originalLength = productsToProcess.length;
          productsToProcess = productsToProcess.filter(_this._doesProductHaveSkus);
          filteredProductsLength = originalLength - productsToProcess.length;
          if (filteredProductsLength) {
            _this.logger.warn("Filtering out " + filteredProductsLength + " product(s) which do not have SKU");
            _this._summary.productsWithMissingSKU += filteredProductsLength;
          }
          skus = _this._extractUniqueSkus(productsToProcess);
          if (skus.length) {
            return _this._getExistingProductsForSkus(skus);
          } else {
            return [];
          }
        }).then(function(queriedEntries) {
          var reassignmentService;
          if (_this.variantReassignmentOptions.enabled) {
            _this.logger.debug('execute reassignment process');
            reassignmentService = new Reassignment(_this.client, _this.logger, _this.variantReassignmentOptions.retainExistingData);
            return reassignmentService.execute(productsToProcess, _this._cache.productType).then(function(statistics) {
              var skus;
              _this._summary.variantReassignment = statistics;
              if (statistics.processed > 0) {
                skus = _this._extractUniqueSkus(productsToProcess);
                if (skus.length) {
                  return _this._getExistingProductsForSkus(skus);
                } else {
                  return queriedEntries;
                }
              } else {
                return queriedEntries;
              }
            });
          } else {
            return queriedEntries;
          }
        }).then(function(queriedEntries) {
          if (_this.defaultAttributesService) {
            debug('Ensuring default attributes');
            return _this._ensureDefaultAttributesInProducts(productsToProcess, queriedEntries).then(function() {
              return Promise.resolve(queriedEntries);
            });
          } else {
            return Promise.resolve(queriedEntries);
          }
        }).then(function(queriedEntries) {
          return _this._createOrUpdate(productsToProcess, queriedEntries);
        }).then(function(results) {
          _.each(results, function(r) {
            return _this._handleProcessResponse(r);
          });
          return Promise.resolve(_this._summary);
        });
      };
    })(this), {
      concurrency: 1
    });
  };

  ProductImport.prototype._getWhereQueryLimit = function() {
    var client, url;
    client = this.client.productProjections.where('a').staged(true);
    url = _.clone(this.client.productProjections._rest._options.uri);
    url = url.replace(/.*?:\/\//g, "");
    url += this.client.productProjections._currentEndpoint;
    url += "?" + this.client.productProjections._queryString();
    this.client.productProjections._setDefaults();
    return this.urlLimit - Buffer.byteLength(url, 'utf-8') - 1;
  };

  ProductImport.prototype._getExistingProductsForSkus = function(skus) {
    return new Promise((function(_this) {
      return function(resolve, reject) {
        var skuChunks;
        skuChunks = _this.commonUtils._separateSkusChunksIntoSmallerChunks(skus, _this._getWhereQueryLimit());
        return Promise.map(skuChunks, function(skus) {
          var predicate;
          predicate = _this._createProductFetchBySkuQueryPredicate(skus);
          return _this.client.productProjections.where(predicate).staged(true).perPage(200).all().fetch().then(function(res) {
            return res.body.results;
          });
        }, {
          concurrency: 30
        }).then(function(results) {
          debug('Fetched products: %j', results);
          return resolve(_.flatten(results));
        })["catch"](function(err) {
          return reject(err);
        });
      };
    })(this));
  };

  ProductImport.prototype._errorLogger = function(res, logger) {
    if (this._summary.failed < this.errorLimit || this.errorLimit === 0) {
      return logger.error(res, "Skipping product due to an error");
    } else {
      return logger.warn("Error not logged as error limit of " + this.errorLimit + " has reached.");
    }
  };

  ProductImport.prototype._handleProcessResponse = function(res) {
    var error, errorFile;
    if (res.isFulfilled()) {
      return this._handleFulfilledResponse(res);
    } else if (res.isRejected()) {
      error = serializeError(res.reason());
      this._summary.failed++;
      if (this.errorDir) {
        errorFile = path.join(this.errorDir, "error-" + this._summary.failed + ".json");
        fs.outputJsonSync(errorFile, error, {
          spaces: 2
        });
      }
      if (_.isFunction(this.errorCallback)) {
        return this.errorCallback(error, this.logger);
      } else {
        return this.logger.error("Error callback has to be a function!");
      }
    }
  };

  ProductImport.prototype._handleFulfilledResponse = function(res) {
    switch (res.value().statusCode) {
      case 201:
        return this._summary.created++;
      case 200:
        return this._summary.updated++;
    }
  };

  ProductImport.prototype._createProductFetchBySkuQueryPredicate = function(skus) {
    var skuString;
    skuString = "sku in (" + (skus.map(function(val) {
      return JSON.stringify(val);
    })) + ")";
    return "masterVariant(" + skuString + ") or variants(" + skuString + ")";
  };

  ProductImport.prototype._doesProductHaveSkus = function(product) {
    var i, len, ref2, ref3, variant;
    if (product.masterVariant && !product.masterVariant.sku) {
      return false;
    }
    if ((ref2 = product.variants) != null ? ref2.length : void 0) {
      ref3 = product.variants;
      for (i = 0, len = ref3.length; i < len; i++) {
        variant = ref3[i];
        if (!variant.sku) {
          return false;
        }
      }
    }
    return true;
  };

  ProductImport.prototype._extractUniqueSkus = function(products) {
    var i, j, len, len1, product, ref2, ref3, ref4, skus, variant;
    skus = [];
    for (i = 0, len = products.length; i < len; i++) {
      product = products[i];
      if ((ref2 = product.masterVariant) != null ? ref2.sku : void 0) {
        skus.push(product.masterVariant.sku);
      }
      if ((ref3 = product.variants) != null ? ref3.length : void 0) {
        ref4 = product.variants;
        for (j = 0, len1 = ref4.length; j < len1; j++) {
          variant = ref4[j];
          if (variant.sku) {
            skus.push(variant.sku);
          }
        }
      }
    }
    return _.uniq(skus, false);
  };

  ProductImport.prototype._isExistingEntry = function(prodToProcess, existingProducts) {
    var prodToProcessSkus;
    prodToProcessSkus = this._extractUniqueSkus([prodToProcess]);
    return _.find(existingProducts, (function(_this) {
      return function(existingEntry) {
        var existingProductSkus, matchingSkus;
        existingProductSkus = _this._extractUniqueSkus([existingEntry]);
        matchingSkus = _.intersection(prodToProcessSkus, existingProductSkus);
        if (matchingSkus.length > 0) {
          return true;
        } else {
          return false;
        }
      };
    })(this));
  };

  ProductImport.prototype._updateProductRepeater = function(prodToProcess, existingProduct) {
    var repeater;
    repeater = new Repeater({
      attempts: 5
    });
    return repeater.execute((function(_this) {
      return function() {
        return _this._updateProduct(prodToProcess, existingProduct);
      };
    })(this), (function(_this) {
      return function(e) {
        if (e.statusCode !== 409) {
          return Promise.reject(e);
        }
        _this.logger.warn("Recovering from 409 concurrentModification error on product '" + existingProduct.id + "'");
        return Promise.resolve(function() {
          return _this.client.productProjections.staged(true).byId(existingProduct.id).fetch().then(function(result) {
            return _this._updateProduct(prodToProcess, result.body, true);
          });
        });
      };
    })(this));
  };

  ProductImport.prototype._updateProduct = function(prodToProcess, existingProduct, productIsPrepared) {
    return this._fetchSameForAllAttributesOfProductType(prodToProcess.productType).then((function(_this) {
      return function(sameForAllAttributes) {
        var productPromise;
        productPromise = Promise.resolve(prodToProcess);
        if (!productIsPrepared) {
          productPromise = _this._prepareUpdateProduct(prodToProcess, existingProduct);
        }
        return productPromise.then(function(preparedProduct) {
          var synced;
          synced = _this.sync.buildActions(preparedProduct, existingProduct, sameForAllAttributes).filterActions(function(action) {
            return _this.filterActions(action, existingProduct, preparedProduct);
          });
          if (synced.shouldUpdate()) {
            return _this._updateInBatches(synced.getUpdateId(), synced.getUpdatePayload());
          } else {
            return Promise.resolve({
              statusCode: 304
            });
          }
        });
      };
    })(this));
  };

  ProductImport.prototype._updateInBatches = function(id, updateRequest) {
    var batchedActions, latestVersion;
    latestVersion = updateRequest.version;
    batchedActions = _.batchList(updateRequest.actions, 500);
    return Promise.mapSeries(batchedActions, (function(_this) {
      return function(actions) {
        var request;
        request = {
          version: latestVersion,
          actions: actions
        };
        return _this.client.products.byId(id).update(request).tap(function(res) {
          return latestVersion = res.body.version;
        });
      };
    })(this)).then(_.last);
  };

  ProductImport.prototype._cleanVariantAttributes = function(variant) {
    var attributeMap;
    attributeMap = [];
    if (_.isArray(variant.attributes)) {
      return variant.attributes = variant.attributes.filter((function(_this) {
        return function(attribute) {
          var isDuplicate, msg;
          isDuplicate = attributeMap.indexOf(attribute.name) >= 0;
          attributeMap.push(attribute.name);
          if (isDuplicate) {
            msg = "Variant with SKU '" + variant.sku + "' has duplicate attributes with name '" + attribute.name + "'.";
            if (_this.failOnDuplicateAttr) {
              throw new Error(msg);
            } else if (_this.logOnDuplicateAttr) {
              _this.logger.warn(msg);
            }
          }
          return !isDuplicate;
        };
      })(this));
    }
  };

  ProductImport.prototype._cleanDuplicateAttributes = function(prodToProcess) {
    prodToProcess.variants = prodToProcess.variants || [];
    this._cleanVariantAttributes(prodToProcess.masterVariant);
    return prodToProcess.variants.forEach((function(_this) {
      return function(variant) {
        return _this._cleanVariantAttributes(variant);
      };
    })(this));
  };

  ProductImport.prototype._createOrUpdate = function(productsToProcess, existingProducts) {
    var posts;
    debug('Products to process: %j', {
      toProcess: productsToProcess,
      existing: existingProducts
    });
    posts = _.map(productsToProcess, (function(_this) {
      return function(product) {
        return _this._filterAttributes(product).then(function(prodToProcess) {
          var existingProduct;
          _this._cleanDuplicateAttributes(prodToProcess);
          existingProduct = _this._isExistingEntry(prodToProcess, existingProducts);
          if (existingProduct != null) {
            return _this._updateProductRepeater(prodToProcess, existingProduct);
          } else {
            return _this._prepareNewProduct(prodToProcess).then(function(product) {
              return _this.client.products.create(product);
            });
          }
        });
      };
    })(this));
    debug('About to send %s requests', _.size(posts));
    return Promise.settle(posts);
  };

  ProductImport.prototype._filterAttributes = function(product) {
    return new Promise((function(_this) {
      return function(resolve) {
        if (_this.filterUnknownAttributes) {
          return _this.unknownAttributesFilter.filter(_this._cache.productType[product.productType.id], product, _this._summary.unknownAttributeNames).then(function(filteredProduct) {
            return resolve(filteredProduct);
          });
        } else {
          return resolve(product);
        }
      };
    })(this));
  };

  ProductImport.prototype._filterUniqueUpdateActions = function(updateActions) {
    return _.reduce(_.keys(updateActions), (function(_this) {
      return function(acc, productTypeId) {
        var actions, uniqueActions;
        actions = updateActions[productTypeId];
        uniqueActions = _this.commonUtils.uniqueObjectFilter(actions);
        acc[productTypeId] = uniqueActions;
        return acc;
      };
    })(this), {});
  };

  ProductImport.prototype._ensureProductTypesInMemory = function(products) {
    return Promise.map(products, (function(_this) {
      return function(product) {
        return _this._ensureProductTypeInMemory(product.productType.id);
      };
    })(this), {
      concurrency: 1
    });
  };

  ProductImport.prototype._ensureDefaultAttributesInProducts = function(products, queriedEntries) {
    if (queriedEntries) {
      queriedEntries = _.compact(queriedEntries);
    }
    return Promise.map(products, (function(_this) {
      return function(product) {
        var productFromServer, uniqueSkus;
        if ((queriedEntries != null ? queriedEntries.length : void 0) > 0) {
          uniqueSkus = _this._extractUniqueSkus([product]);
          productFromServer = _.find(queriedEntries, function(entry) {
            var intersection, serverUniqueSkus;
            serverUniqueSkus = _this._extractUniqueSkus([entry]);
            intersection = _.intersection(uniqueSkus, serverUniqueSkus);
            return _.compact(intersection).length > 0;
          });
        }
        return _this.defaultAttributesService.ensureDefaultAttributesInProduct(product, productFromServer);
      };
    })(this), {
      concurrency: 1
    });
  };

  ProductImport.prototype._ensureProductTypeInMemory = function(productTypeId) {
    var productType;
    if (this._cache.productType[productTypeId]) {
      return Promise.resolve();
    } else {
      productType = {
        id: productTypeId
      };
      return this._resolveReference(this.client.productTypes, 'productType', productType, "name=\"" + (productType != null ? productType.id : void 0) + "\"");
    }
  };

  ProductImport.prototype._validateEnums = function(products) {
    var enumUpdateActions;
    enumUpdateActions = {};
    _.each(products, (function(_this) {
      return function(product) {
        var updateActions;
        updateActions = _this.enumValidator.validateProduct(product, _this._cache.productType[product.productType.id]);
        if (updateActions && _.size(updateActions.actions) > 0) {
          return _this._updateEnumUpdateActions(enumUpdateActions, updateActions);
        }
      };
    })(this));
    return enumUpdateActions;
  };

  ProductImport.prototype._updateProductType = function(enumUpdateActions) {
    if (_.isEmpty(enumUpdateActions)) {
      return Promise.resolve();
    } else {
      debug("Updating product type(s): " + (_.keys(enumUpdateActions)));
      return Promise.map(_.keys(enumUpdateActions), (function(_this) {
        return function(productTypeId) {
          var updateRequest;
          updateRequest = {
            version: _this._cache.productType[productTypeId].version,
            actions: enumUpdateActions[productTypeId]
          };
          return _this.client.productTypes.byId(_this._cache.productType[productTypeId].id).update(updateRequest).then(function(updatedProductType) {
            _this._cache.productType[productTypeId] = updatedProductType.body;
            return _this._summary.productTypeUpdated++;
          });
        };
      })(this));
    }
  };

  ProductImport.prototype._updateEnumUpdateActions = function(enumUpdateActions, updateActions) {
    if (enumUpdateActions[updateActions.productTypeId]) {
      return enumUpdateActions[updateActions.productTypeId] = enumUpdateActions[updateActions.productTypeId].concat(updateActions.actions);
    } else {
      return enumUpdateActions[updateActions.productTypeId] = updateActions.actions;
    }
  };

  ProductImport.prototype._fetchSameForAllAttributesOfProductType = function(productType) {
    if (this._cache.productType[productType.id + "_sameForAllAttributes"]) {
      return Promise.resolve(this._cache.productType[productType.id + "_sameForAllAttributes"]);
    } else {
      return this._resolveReference(this.client.productTypes, 'productType', productType, "name=\"" + (productType != null ? productType.id : void 0) + "\"").then((function(_this) {
        return function() {
          var sameValueAttributeNames, sameValueAttributes;
          sameValueAttributes = _.where(_this._cache.productType[productType.id].attributes, {
            attributeConstraint: "SameForAll"
          });
          sameValueAttributeNames = _.pluck(sameValueAttributes, 'name');
          _this._cache.productType[productType.id + "_sameForAllAttributes"] = sameValueAttributeNames;
          return Promise.resolve(sameValueAttributeNames);
        };
      })(this));
    }
  };

  ProductImport.prototype._ensureVariantDefaults = function(variant) {
    var variantDefaults;
    if (variant == null) {
      variant = {};
    }
    variantDefaults = {
      attributes: [],
      prices: [],
      images: []
    };
    return _.defaults(variant, variantDefaults);
  };

  ProductImport.prototype._ensureDefaults = function(product) {
    debug('ensuring default fields in variants.');
    _.defaults(product, {
      masterVariant: this._ensureVariantDefaults(product.masterVariant),
      variants: _.map(product.variants, (function(_this) {
        return function(variant) {
          return _this._ensureVariantDefaults(variant);
        };
      })(this))
    });
    return product;
  };

  ProductImport.prototype._prepareUpdateProduct = function(productToProcess, existingProduct) {
    var ref2;
    productToProcess = this._ensureDefaults(productToProcess);
    return Promise.all([this._resolveProductCategories(productToProcess.categories), this._resolveReference(this.client.taxCategories, 'taxCategory', productToProcess.taxCategory, "name=\"" + ((ref2 = productToProcess.taxCategory) != null ? ref2.id : void 0) + "\""), this._fetchAndResolveCustomReferences(productToProcess)]).spread((function(_this) {
      return function(prodCatsIds, taxCatId) {
        if (taxCatId) {
          productToProcess.taxCategory = {
            id: taxCatId,
            typeId: 'tax-category'
          };
        }
        if (prodCatsIds) {
          productToProcess.categories = _.map(prodCatsIds, function(catId) {
            return {
              id: catId,
              typeId: 'category'
            };
          });
        }
        productToProcess.slug = _this._updateProductSlug(productToProcess, existingProduct);
        return Promise.resolve(productToProcess);
      };
    })(this));
  };

  ProductImport.prototype._updateProductSlug = function(productToProcess, existingProduct) {
    var slug;
    if (this.ignoreSlugUpdates) {
      slug = existingProduct.slug;
    } else if (!productToProcess.slug) {
      debug('slug missing in product to process, assigning same as existing product: %s', existingProduct.slug);
      slug = existingProduct.slug;
    } else {
      slug = productToProcess.slug;
    }
    return slug;
  };

  ProductImport.prototype._prepareNewProduct = function(product) {
    var ref2, ref3;
    product = this._ensureDefaults(product);
    return Promise.all([this._resolveReference(this.client.productTypes, 'productType', product.productType, "name=\"" + ((ref2 = product.productType) != null ? ref2.id : void 0) + "\""), this._resolveProductCategories(product.categories), this._resolveReference(this.client.taxCategories, 'taxCategory', product.taxCategory, "name=\"" + ((ref3 = product.taxCategory) != null ? ref3.id : void 0) + "\""), this._fetchAndResolveCustomReferences(product)]).spread((function(_this) {
      return function(prodTypeId, prodCatsIds, taxCatId) {
        if (prodTypeId) {
          product.productType = {
            id: prodTypeId,
            typeId: 'product-type'
          };
        }
        if (taxCatId) {
          product.taxCategory = {
            id: taxCatId,
            typeId: 'tax-category'
          };
        }
        if (prodCatsIds) {
          product.categories = _.map(prodCatsIds, function(catId) {
            return {
              id: catId,
              typeId: 'category'
            };
          });
        }
        if (!product.slug) {
          if (product.name) {
            product.slug = _this._generateSlug(product.name);
          }
        }
        return Promise.resolve(product);
      };
    })(this));
  };

  ProductImport.prototype._generateSlug = function(name) {
    var slugs;
    slugs = _.mapObject(name, (function(_this) {
      return function(val) {
        var uniqueToken;
        uniqueToken = _this._generateUniqueToken();
        return slugify(val).concat("-" + uniqueToken).substring(0, 256);
      };
    })(this));
    return slugs;
  };

  ProductImport.prototype._generateUniqueToken = function() {
    return _.uniqueId("" + (new Date().getTime()));
  };

  ProductImport.prototype._fetchAndResolveCustomReferences = function(product) {
    return Promise.all([
      this._fetchAndResolveCustomReferencesByVariant(product.masterVariant), Promise.map(product.variants, (function(_this) {
        return function(variant) {
          return _this._fetchAndResolveCustomReferencesByVariant(variant);
        };
      })(this), {
        concurrency: 5
      })
    ]).spread(function(masterVariant, variants) {
      return Promise.resolve(_.extend(product, {
        masterVariant: masterVariant,
        variants: variants
      }));
    });
  };

  ProductImport.prototype._fetchAndResolveCustomAttributeReferences = function(variant) {
    if (variant.attributes && !_.isEmpty(variant.attributes)) {
      return Promise.map(variant.attributes, (function(_this) {
        return function(attribute) {
          if (attribute && _.isArray(attribute.value)) {
            if (_.every(attribute.value, _this._isReferenceTypeAttribute)) {
              return _this._resolveCustomReferenceSet(attribute.value).then(function(result) {
                attribute.value = result;
                return Promise.resolve(attribute);
              });
            } else {
              return Promise.resolve(attribute);
            }
          } else {
            if (attribute && _this._isReferenceTypeAttribute(attribute)) {
              return _this._resolveCustomReference(attribute).then(function(refId) {
                return Promise.resolve({
                  name: attribute.name,
                  value: {
                    id: refId,
                    typeId: attribute.type.referenceTypeId
                  }
                });
              });
            } else {
              return Promise.resolve(attribute);
            }
          }
        };
      })(this)).then(function(attributes) {
        return Promise.resolve(_.extend(variant, {
          attributes: attributes
        }));
      });
    } else {
      return Promise.resolve(variant);
    }
  };

  ProductImport.prototype._fetchAndResolveCustomPriceReferences = function(variant) {
    if (variant.prices && !_.isEmpty(variant.prices)) {
      return Promise.map(variant.prices, (function(_this) {
        return function(price) {
          var ref, service;
          if (price && price.custom && price.custom.type && price.custom.type.id) {
            service = _this.client.types;
            ref = {
              id: price.custom.type.id
            };
            return _this._resolveReference(service, "types", ref, "key=\"" + ref.id + "\"").then(function(refId) {
              price.custom.type.id = refId;
              return Promise.resolve(price);
            });
          } else {
            return Promise.resolve(price);
          }
        };
      })(this)).then(function(prices) {
        return Promise.resolve(_.extend(variant, {
          prices: prices
        }));
      });
    } else {
      return Promise.resolve(variant);
    }
  };

  ProductImport.prototype._fetchAndResolveCustomReferencesByVariant = function(variant) {
    return this._fetchAndResolveCustomAttributeReferences(variant).then((function(_this) {
      return function(variant) {
        return _this._fetchAndResolveCustomPriceReferences(variant);
      };
    })(this));
  };

  ProductImport.prototype._resolveCustomReferenceSet = function(attributeValue) {
    return Promise.map(attributeValue, (function(_this) {
      return function(referenceObject) {
        return _this._resolveCustomReference(referenceObject);
      };
    })(this));
  };

  ProductImport.prototype._isReferenceTypeAttribute = function(attribute) {
    return _.has(attribute, 'type') && attribute.type.name === 'reference';
  };

  ProductImport.prototype._resolveCustomReference = function(referenceObject) {
    var predicate, ref, refKey, service;
    service = (function() {
      switch (referenceObject.type.referenceTypeId) {
        case 'product':
          return this.client.productProjections;
      }
    }).call(this);
    refKey = referenceObject.type.referenceTypeId;
    ref = _.deepClone(referenceObject);
    ref.id = referenceObject.value;
    predicate = referenceObject._custom.predicate;
    return this._resolveReference(service, refKey, ref, predicate);
  };

  ProductImport.prototype._resolveProductCategories = function(cats) {
    return new Promise((function(_this) {
      return function(resolve, reject) {
        if (_.isEmpty(cats)) {
          return resolve();
        } else {
          return Promise.all(cats.map(function(cat) {
            return _this._resolveReference(_this.client.categories, 'categories', cat, "externalId=\"" + cat.id + "\"");
          })).then(function(result) {
            return resolve(result.filter(function(c) {
              return c;
            }));
          })["catch"](function(err) {
            return reject(err);
          });
        }
      };
    })(this));
  };

  ProductImport.prototype._resolveReference = function(service, refKey, ref, predicate) {
    return new Promise((function(_this) {
      return function(resolve, reject) {
        var request;
        if (!ref) {
          resolve();
        }
        if (!_this._cache[refKey]) {
          _this._cache[refKey] = {};
        }
        if (_this._cache[refKey][ref.id]) {
          return resolve(_this._cache[refKey][ref.id].id);
        } else {
          request = service.where(predicate);
          if (refKey === 'product') {
            request.staged(true);
          }
          return request.fetch().then(function(result) {
            if (result.body.count === 0) {
              return reject("Didn't find any match while resolving " + refKey + " (" + predicate + ")");
            } else {
              if (_.size(result.body.results) > 1) {
                _this.logger.warn("Found more than 1 " + refKey + " for " + ref.id);
              }
              _this._cache[refKey][ref.id] = result.body.results[0];
              if (refKey === 'productType') {
                _this._cache[refKey][result.body.results[0].id] = result.body.results[0];
              }
              return resolve(result.body.results[0].id);
            }
          });
        }
      };
    })(this));
  };

  return ProductImport;

})();

module.exports = ProductImport;
