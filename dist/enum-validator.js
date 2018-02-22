var EnumValidator, Promise, SphereClient, _, debug, slugify,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

debug = require('debug')('sphere-product-import:enum-validator');

_ = require('underscore');

_.mixin(require('underscore-mixins'));

Promise = require('bluebird');

slugify = require('underscore.string/slugify');

SphereClient = require('sphere-node-sdk').SphereClient;

EnumValidator = (function() {
  function EnumValidator(logger) {
    this.logger = logger;
    this._extractEnumAttributesFromProductType = bind(this._extractEnumAttributesFromProductType, this);
    this._fetchEnumAttributeNamesOfProductType = bind(this._fetchEnumAttributeNamesOfProductType, this);
    this._fetchEnumAttributesOfProductType = bind(this._fetchEnumAttributesOfProductType, this);
    this._fetchEnumAttributesFromVariant = bind(this._fetchEnumAttributesFromVariant, this);
    this._fetchEnumAttributesFromProduct = bind(this._fetchEnumAttributesFromProduct, this);
    this._generateEnumSetUpdateAction = bind(this._generateEnumSetUpdateAction, this);
    this._generateMultipleValueEnumSetUpdateAction = bind(this._generateMultipleValueEnumSetUpdateAction, this);
    this._generateEnumSetUpdateActionByValueType = bind(this._generateEnumSetUpdateActionByValueType, this);
    this._generateUpdateAction = bind(this._generateUpdateAction, this);
    this._isEnumGenerated = bind(this._isEnumGenerated, this);
    this._handleNewEnumAttributeUpdate = bind(this._handleNewEnumAttributeUpdate, this);
    this._validateEnums = bind(this._validateEnums, this);
    this.validateProduct = bind(this.validateProduct, this);
    this._resetCache();
    debug("Enum Validator initialized.");
  }

  EnumValidator.prototype._resetCache = function() {
    return this._cache = {
      productTypeEnumMap: {},
      generatedEnums: {}
    };
  };

  EnumValidator.prototype.validateProduct = function(product, resolvedProductType) {
    var enumAttributes, update, updateActions;
    enumAttributes = this._fetchEnumAttributesFromProduct(product, resolvedProductType);
    updateActions = this._validateEnums(enumAttributes, resolvedProductType);
    update = {
      productTypeId: resolvedProductType.id,
      actions: updateActions
    };
    return update;
  };

  EnumValidator.prototype._validateEnums = function(enumAttributes, productType) {
    var ea, i, len, referenceEnums, updateActions;
    updateActions = [];
    referenceEnums = this._fetchEnumAttributesOfProductType(productType);
    for (i = 0, len = enumAttributes.length; i < len; i++) {
      ea = enumAttributes[i];
      if (!this._isEnumGenerated(ea)) {
        this._handleNewEnumAttributeUpdate(ea, referenceEnums, updateActions, productType);
      } else {
        debug("Skipping " + ea.name + " update action generation as already exists.");
      }
    }
    return updateActions;
  };

  EnumValidator.prototype._handleNewEnumAttributeUpdate = function(ea, referenceEnums, updateActions, productType) {
    var refEnum;
    refEnum = _.findWhere(referenceEnums, {
      name: "" + ea.name
    });
    if (refEnum && !this._isEnumKeyPresent(ea, refEnum)) {
      return updateActions.push(this._generateUpdateAction(ea, refEnum));
    } else {
      return debug("enum attribute name: " + ea.name + " not found in Product Type: " + productType.name);
    }
  };

  EnumValidator.prototype._isEnumGenerated = function(ea) {
    return this._cache.generatedEnums[ea.name + "-" + (slugify(ea.value))];
  };

  EnumValidator.prototype._generateUpdateAction = function(enumAttribute, refEnum) {
    switch (refEnum.type.name) {
      case 'enum':
        return this._generateEnumUpdateAction(enumAttribute, refEnum);
      case 'lenum':
        return this._generateLenumUpdateAction(enumAttribute, refEnum);
      case 'set':
        return this._generateEnumSetUpdateActionByValueType(enumAttribute, refEnum);
      default:
        throw err("Invalid enum type: " + refEnum.type.name);
    }
  };

  EnumValidator.prototype._generateEnumSetUpdateActionByValueType = function(enumAttribute, refEnum) {
    if (_.isArray(enumAttribute.value)) {
      return this._generateMultipleValueEnumSetUpdateAction(enumAttribute, refEnum);
    } else {
      return this._generateEnumSetUpdateAction(enumAttribute, refEnum);
    }
  };

  EnumValidator.prototype._generateMultipleValueEnumSetUpdateAction = function(enumAttribute, refEnum) {
    return _.map(enumAttribute.value, (function(_this) {
      return function(attributeValue) {
        var ea;
        ea = {
          name: enumAttribute.name,
          value: attributeValue
        };
        return _this._generateEnumSetUpdateAction(ea, refEnum);
      };
    })(this));
  };

  EnumValidator.prototype._generateEnumSetUpdateAction = function(enumAttribute, refEnum) {
    switch (refEnum.type.elementType.name) {
      case 'enum':
        return this._generateEnumUpdateAction(enumAttribute, refEnum);
      case 'lenum':
        return this._generateLenumUpdateAction(enumAttribute, refEnum);
      default:
        throw err("Invalid set enum type: " + refEnum.type.elementType.name);
    }
  };

  EnumValidator.prototype._generateEnumUpdateAction = function(ea, refEnum) {
    var updateAction;
    updateAction = {
      action: 'addPlainEnumValue',
      attributeName: refEnum.name,
      value: {
        key: slugify(ea.value),
        label: ea.value
      }
    };
    return updateAction;
  };

  EnumValidator.prototype._generateLenumUpdateAction = function(ea, refEnum) {
    var updateAction;
    updateAction = {
      action: 'addLocalizedEnumValue',
      attributeName: refEnum.name,
      value: {
        key: slugify(ea.value),
        label: {
          en: ea.value,
          de: ea.value,
          fr: ea.value,
          it: ea.value,
          es: ea.value
        }
      }
    };
    return updateAction;
  };

  EnumValidator.prototype._isEnumKeyPresent = function(enumAttribute, refEnum) {
    if (refEnum.type.name === 'set') {
      return _.findWhere(refEnum.type.elementType.values, {
        key: slugify(enumAttribute.value)
      });
    } else {
      return _.findWhere(refEnum.type.values, {
        key: slugify(enumAttribute.value)
      });
    }
  };

  EnumValidator.prototype._fetchEnumAttributesFromProduct = function(product, resolvedProductType) {
    var enumAttributes, i, len, ref, variant;
    enumAttributes = this._fetchEnumAttributesFromVariant(product.masterVariant, resolvedProductType);
    if (product.variants && !_.isEmpty(product.variants)) {
      ref = product.variants;
      for (i = 0, len = ref.length; i < len; i++) {
        variant = ref[i];
        enumAttributes = enumAttributes.concat(this._fetchEnumAttributesFromVariant(variant, resolvedProductType));
      }
    }
    return enumAttributes;
  };

  EnumValidator.prototype._fetchEnumAttributesFromVariant = function(variant, productType) {
    var attribute, enums, i, len, productTypeEnumNames, ref;
    enums = [];
    productTypeEnumNames = this._fetchEnumAttributeNamesOfProductType(productType);
    ref = variant.attributes;
    for (i = 0, len = ref.length; i < len; i++) {
      attribute = ref[i];
      if (this._isEnumVariantAttribute(attribute, productTypeEnumNames)) {
        enums.push(attribute);
      }
    }
    return enums;
  };

  EnumValidator.prototype._isEnumVariantAttribute = function(attribute, productTypeEnums) {
    var ref;
    return ref = attribute.name, indexOf.call(productTypeEnums, ref) >= 0;
  };

  EnumValidator.prototype._fetchEnumAttributesOfProductType = function(productType) {
    return this._extractEnumAttributesFromProductType(productType);
  };

  EnumValidator.prototype._fetchEnumAttributeNamesOfProductType = function(productType) {
    var enums, names;
    if (this._cache.productTypeEnumMap[productType.id + "_names"]) {
      return this._cache.productTypeEnumMap[productType.id + "_names"];
    } else {
      enums = this._fetchEnumAttributesOfProductType(productType);
      names = _.pluck(enums, 'name');
      this._cache.productTypeEnumMap[productType.id + "_names"] = names;
      return names;
    }
  };

  EnumValidator.prototype._extractEnumAttributesFromProductType = function(productType) {
    return _.filter(productType.attributes, this._enumLenumFilterPredicate).concat(_.filter(productType.attributes, this._enumSetFilterPredicate)).concat(_.filter(productType.attributes, this._lenumSetFilterPredicate));
  };

  EnumValidator.prototype._enumLenumFilterPredicate = function(attribute) {
    return attribute.type.name === 'enum' || attribute.type.name === 'lenum';
  };

  EnumValidator.prototype._enumSetFilterPredicate = function(attribute) {
    return attribute.type.name === 'set' && attribute.type.elementType.name === 'enum';
  };

  EnumValidator.prototype._lenumSetFilterPredicate = function(attribute) {
    return attribute.type.name === 'set' && attribute.type.elementType.name === 'lenum';
  };

  return EnumValidator;

})();

module.exports = EnumValidator;
