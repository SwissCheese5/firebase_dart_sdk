// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/bound.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/event_manager.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/order_by.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart'
    as core;
import 'package:firebase_firestore/src/firebase/firestore/core/query_listener.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/relation_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/listener_registration.dart';
import 'package:firebase_firestore/src/firebase/firestore/metadata_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart'
    as core;
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/reference_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/source.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/executor_event_listener.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/listener_registration_impl.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';

/// An enum for the direction of a sort.
// TODO: Remove this annotation once our proguard issues are sorted out.
enum Direction { ASCENDING, DESCENDING }

/// A Query which you can read or listen to. You can also construct refined Query objects by adding
/// filters and ordering.
///
/// * <b>Subclassing Note</b>: Firestore classes are not meant to be subclassed except for use in
/// test mocks. Subclassing is not supported in production code and new SDK releases may break code
/// that does so.
@publicApi
class Query {
  final core.Query query;

  final FirebaseFirestore firestore;

  Query(this.query, this.firestore)
      : assert(query != null),
        assert(firestore != null);

  /*private*/
  void validateOrderByFieldMatchesInequality(
      core.FieldPath orderBy, core.FieldPath inequality) {
    if (orderBy != inequality) {
      final String inequalityString = inequality.canonicalString;
      throw ArgumentError(
          'Invalid query. You have an inequality where filter (whereLessThan(), '
          'whereGreaterThan(), etc.) on field "$inequalityString" and so you must also have "$inequalityString" as '
          'your first orderBy() field, but your first orderBy() is currently on field '
          '"${orderBy.canonicalString}" instead.');
    }
  }

  /*private*/
  void validateNewFilter(Filter filter) {
    if (filter is RelationFilter) {
      final RelationFilter relationFilter = filter;
      if (relationFilter.isInequality) {
        final core.FieldPath existingInequality = query.inequalityField();
        final core.FieldPath newInequality = filter.field;

        if (existingInequality != null && existingInequality != newInequality) {
          throw ArgumentError(
            'All where filters other than whereEqualTo() must be on the same field. '
                'But you have filters on "${existingInequality.canonicalString}" and "${newInequality.canonicalString}"',
          );
        }
        final core.FieldPath firstOrderByField = query.getFirstOrderByField();
        if (firstOrderByField != null) {
          validateOrderByFieldMatchesInequality(
              firstOrderByField, newInequality);
        }
      } else if (relationFilter.operator == FilterOperator.arrayContains) {
        if (query.hasArrayContainsFilter()) {
          throw ArgumentError(
              'Invalid Query. Queries only support having a single array-contains filter.');
        }
      }
    }
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field and the value should be equal to the
  /// specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  /// Returns the created [Query].
  @publicApi
  Query whereEqualTo(String field, Object value) {
    return whereHelper(
        FieldPath.fromDotSeparatedPath(field), FilterOperator.equal, value);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field and the value should be equal
  /// to the specified value.
  ///
  /// [fieldPath] The path of the field to compare
  /// [value] The value for comparison
  /// Returns the created [Query].
  @publicApi
  Query wherePathEqualTo(FieldPath fieldPath, Object value) {
    return whereHelper(fieldPath, FilterOperator.equal, value);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field and the value should be less
  /// than the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  /// Returns the created [Query].
  @publicApi
  Query whereLessThan(String field, Object value) {
    return whereHelper(
        FieldPath.fromDotSeparatedPath(field), FilterOperator.lessThan, value);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field and the value should be less
  /// than the specified value.
  ///
  /// [fieldPath] The path of the field to compare
  /// [value] The value for comparison
  /// Returns the created [Query].
  @publicApi
  Query wherePathLessThan(FieldPath fieldPath, Object value) {
    return whereHelper(fieldPath, FilterOperator.lessThan, value);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field and the value should be less
  /// than or equal to the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  /// Returns the created [Query].
  @publicApi
  Query whereLessThanOrEqualTo(String field, Object value) {
    return whereHelper(FieldPath.fromDotSeparatedPath(field),
        FilterOperator.lessThanOrEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field and the value should be less
  /// than or equal to the specified value.
  ///
  /// [fieldPath] The path of the field to compare
  /// [value] The value for comparison
  /// Returns the created [Query].
  @publicApi
  Query wherePathLessThanOrEqualTo(FieldPath fieldPath, Object value) {
    return whereHelper(fieldPath, FilterOperator.lessThanOrEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field and the value should be greater
  /// than the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  /// Returns the created [Query].
  @publicApi
  Query whereGreaterThan(String field, Object value) {
    return whereHelper(FieldPath.fromDotSeparatedPath(field),
        FilterOperator.graterThan, value);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field and the value should be greater
  /// than the specified value.
  ///
  /// [fieldPath] The path of the field to compare
  /// [value] The value for comparison
  /// Returns the created [Query].
  @publicApi
  Query wherePathGreaterThan(FieldPath fieldPath, Object value) {
    return whereHelper(fieldPath, FilterOperator.graterThan, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents
  /// must contain the specified field and the value should be greater than or
  /// equal to the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  /// Returns the created [Query].
  @publicApi
  Query whereGreaterThanOrEqualTo(String field, Object value) {
    return whereHelper(FieldPath.fromDotSeparatedPath(field),
        FilterOperator.graterThanOrEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents
  /// must contain the specified field and the value should be greater than or
  /// equal to the specified value.
  ///
  /// [fieldPath] The path of the field to compare
  /// [value] The value for comparison
  /// Returns the created [Query].
  @publicApi
  Query wherePathGreaterThanOrEqualTo(FieldPath fieldPath, Object value) {
    return whereHelper(fieldPath, FilterOperator.graterThanOrEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field, the value must be an array,
  /// and that the array must contain the provided value.
  ///
  /// * A Query can have only one [whereArrayContains] filter.
  ///
  /// [field] The name of the field containing an array to search
  /// [value] The value that must be contained in the array
  /// Returns the created [Query].
  @publicApi
  Query whereArrayContains(String field, Object value) {
    return whereHelper(FieldPath.fromDotSeparatedPath(field),
        FilterOperator.arrayContains, value);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field, the value must be an array,
  /// and that the array must contain the provided value.
  ///
  /// * A Query can have only one [whereArrayContains] filter.
  /// [fieldPath] The path of the field containing an array to search
  /// [value] The value that must be contained in the array
  /// Returns the created [Query].
  @publicApi
  Query wherePathArrayContains(FieldPath fieldPath, Object value) {
    return whereHelper(fieldPath, FilterOperator.arrayContains, value);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field and the value should satisfy
  /// the relation constraint provided.
  ///
  /// [fieldPath] The field to compare
  /// [op] The operator
  /// [value] The value for comparison
  /// Returns the created Query.
  /*private*/
  Query whereHelper(FieldPath fieldPath, FilterOperator op, Object value) {
    Assert.checkNotNull(fieldPath, 'Provided field path must not be null.');
    Assert.checkNotNull(op, 'Provided op must not be null.');
    FieldValue fieldValue;
    final core.FieldPath internalPath = fieldPath.internalPath;
    if (internalPath.isKeyField) {
      if (op == FilterOperator.arrayContains) {
        throw ArgumentError(
            'Invalid query. You can\'t perform array-contains queries on FieldPath.documentId() since document IDs are not arrays.');
      }
      if (value is String) {
        final String documentKey = value;
        if (documentKey.contains('/')) {
          // TODO: Allow slashes once ancestor queries are supported
          throw ArgumentError(
              'Invalid query. When querying with FieldPath.documentId() you must provide a valid '
              'document ID, but "$documentKey" contains a "/" character.');
        } else if (documentKey.isEmpty) {
          throw ArgumentError(
              'Invalid query. When querying with FieldPath.documentId() you must provide a valid document ID, but it was an empty string.');
        }
        final ResourcePath path = query.path.appendSegment(documentKey);
        Assert.hardAssert(
            path.length.remainder(2) == 0, 'Path should be a document key');
        fieldValue = ReferenceValue.valueOf(
            firestore.databaseId, DocumentKey.fromPath(path));
      } else if (value is DocumentReference) {
        final DocumentReference ref = value;
        fieldValue = ReferenceValue.valueOf(firestore.databaseId, ref.key);
      } else {
        throw ArgumentError(
            'Invalid query. When querying with FieldPath.documentId() you must provide a valid String or DocumentReference, but it was of type: ${Util.typeName(value)}');
      }
    } else {
      fieldValue = firestore.dataConverter.parseQueryValue(value);
    }
    final Filter filter = Filter.create(fieldPath.internalPath, op, fieldValue);
    validateNewFilter(filter);
    return Query(query.filter(filter), firestore);
  }

  /*private*/
  void validateOrderByField(core.FieldPath field) {
    final core.FieldPath inequalityField = query.inequalityField();
    if (query.getFirstOrderByField() == null && inequalityField != null) {
      validateOrderByFieldMatchesInequality(field, inequalityField);
    }
  }

  /// Creates and returns a new [Query] that's additionally sorted by the
  /// specified field. Optionally in descending order instead of ascending.
  ///
  /// [field] the field to sort by.
  /// [direction] the direction to sort.
  /// Returns the created Query.
  @publicApi
  Query orderBy(String field, [Direction direction = Direction.ASCENDING]) {
    return orderByPath(FieldPath.fromDotSeparatedPath(field), direction);
  }

  /// Creates and returns a new [Query] that's additionally sorted by the
  /// specified field, optionally in descending order instead of ascending.
  ///
  /// [fieldPath] the field to sort by.
  /// [direction] the direction to sort.
  /// Returns the created Query.
  @publicApi
  Query orderByPath(FieldPath fieldPath,
      [Direction direction = Direction.ASCENDING]) {
    Assert.checkNotNull(fieldPath, 'Provided field path must not be null.');
    return _orderBy(fieldPath.internalPath, direction);
  }

  Query _orderBy(core.FieldPath fieldPath, Direction direction) {
    Assert.checkNotNull(direction, 'Provided direction must not be null.');
    if (query.getStartAt() != null) {
      throw AssertionError(
          'Invalid query. You must not call Query.startAt() or Query.startAfter() before calling Query.orderBy().');
    }
    if (query.getEndAt() != null) {
      throw ArgumentError(
          'Invalid query. You must not call Query.endAt() or Query.endAfter() before calling Query.orderBy().');
    }
    validateOrderByField(fieldPath);
    final OrderByDirection dir = direction == Direction.ASCENDING
        ? OrderByDirection.ascending
        : OrderByDirection.descending;
    return Query(query.orderBy(OrderBy.getInstance(dir, fieldPath)), firestore);
  }

  /// Creates and returns a new [Query] that's additionally limited to only
  /// return up to the specified number of documents.
  ///
  /// [limit] the maximum number of items to return.
  /// Returns the created Query.
  @publicApi
  Query limit(int limit) {
    if (limit <= 0) {
      throw ArgumentError(
          'Invalid Query. Query limit ($limit) is invalid. Limit must be positive.');
    }
    return Query(query.limit(limit), firestore);
  }

  /// Creates and returns a new [Query] that starts at the provided document
  /// (inclusive). The starting position is relative to the order of the query.
  /// The document must contain all of the fields provided in the orderBy of
  /// this query.
  ///
  /// [snapshot] the snapshot of the document to start at.
  /// Returns the created Query.
  @publicApi
  Query startAtDocument(DocumentSnapshot snapshot) {
    final Bound bound =
        boundFromDocumentSnapshot('startAt', snapshot, /*before:*/ true);
    return Query(query.startAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that starts at the provided fields
  /// relative to the order of the query. The order of the field values must
  /// match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to start this query at, in order of the
  /// query's order by.
  /// Returns the created Query.
  @publicApi
  Query startAt(List<Object> fieldValues) {
    final Bound bound =
        boundFromFields('startAt', fieldValues, /*before:*/ true);
    return Query(query.startAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that starts after the provided document
  /// (exclusive). The starting position is relative to the order of the query.
  /// The document must contain all of the fields provided in the [orderBy] of
  /// this query.
  ///
  /// [snapshot] the snapshot of the document to start after.
  /// Returns the created Query.
  @publicApi
  Query startAfterDocument(DocumentSnapshot snapshot) {
    final Bound bound =
        boundFromDocumentSnapshot('startAfter', snapshot, /*before:*/ false);
    return Query(query.startAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that starts after the provided fields
  /// relative to the order of the query. The order of the field values must
  /// match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to start this query after, in order of the
  /// query's order by.
  /// Returns the created Query.
  @publicApi
  Query startAfter(List<Object> fieldValues) {
    final Bound bound =
        boundFromFields('startAfter', fieldValues, /*before:*/ false);
    return Query(query.startAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that ends before the provided document
  /// (exclusive). The end position is relative to the order of the query. The
  /// document must contain all of the fields provided in the orderBy of this
  /// query.
  ///
  /// [snapshot] the snapshot of the document to end before.
  /// @return The created Query./// Returns the created Query.
  @publicApi
  Query endBeforeDocument(DocumentSnapshot snapshot) {
    final Bound bound =
        boundFromDocumentSnapshot('endBefore', snapshot, /*before:*/ true);
    return Query(query.endAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that ends before the provided fields
  /// relative to the order of the query. The order of the field values must
  /// match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to end this query before, in order of the
  /// query's order by.
  /// Returns the created Query.
  @publicApi
  Query endBefore(List<Object> fieldValues) {
    final Bound bound =
        boundFromFields('endBefore', fieldValues, /*before:*/ true);
    return Query(query.endAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that ends at the provided document
  /// (inclusive). The end position is relative to the order of the query. The
  /// document must contain all of the fields provided in the [orderBy] of this
  /// query.
  ///
  /// [snapshot] the snapshot of the document to end at.
  /// Returns the created Query.
  @publicApi
  Query endAtDocument(DocumentSnapshot snapshot) {
    final Bound bound =
        boundFromDocumentSnapshot('endAt', snapshot, /*before:*/ false);
    return Query(query.endAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that ends at the provided fields
  /// relative to the order of the query. The order of the field values must
  /// match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to end this query at, in order of the
  /// query's order by.
  /// Returns the created Query.
  @publicApi
  Query endAt(List<Object> fieldValues) {
    final Bound bound =
        boundFromFields('endAt', fieldValues, /*before:*/ false);
    return Query(query.endAt(bound), firestore);
  }

  /// Create a [Bound] from a query given the document.
  ///
  /// * Note that the [Bound] will always include the key of the document and so
  /// only the provided document will compare equal to the returned position.
  ///
  /// * Will throw if the document does not contain all fields of the order by
  /// of the query.
  /*private*/
  Bound boundFromDocumentSnapshot(
      String methodName, DocumentSnapshot snapshot, bool before) {
    Assert.checkNotNull<DocumentSnapshot>(
        snapshot, 'Provided snapshot must not be null.');
    if (!snapshot.exists) {
      throw ArgumentError(
          "Can't use a DocumentSnapshot for a document that doesn't exist for $methodName().");
    }
    final Document document = snapshot.document;
    final List<FieldValue> components = <FieldValue>[];

    // Because people expect to continue/end a query at the exact document
    // provided, we need to use the implicit sort order rather than the explicit
    // sort order, because it's guaranteed to contain the document key. That way
    // the position becomes unambiguous and the query continues/ends exactly at
    // the provided document. Without the key (by using the explicit sort
    // orders), multiple documents could match the position, yielding duplicate
    // results.
    for (OrderBy orderBy in query.getOrderBy()) {
      if (orderBy.field == core.FieldPath.keyPath) {
        components
            .add(ReferenceValue.valueOf(firestore.databaseId, document.key));
      } else {
        final FieldValue value = document.getField(orderBy.field);
        if (value != null) {
          components.add(value);
        } else {
          throw ArgumentError(
              'Invalid query. You are trying to start or end a query using a document for which '
              'the field "${orderBy.field}" (used as the orderBy) does not exist.');
        }
      }
    }
    return Bound(components, before);
  }

  /// Converts a list of field values to Bound.
  /*private*/
  Bound boundFromFields(String methodName, List<Object> values, bool before) {
    // Use explicit order by's because it has to match the query the user made
    final List<OrderBy> explicitOrderBy = query.explicitSortOrder;
    if (values.length > explicitOrderBy.length) {
      throw ArgumentError(
          'Too many arguments provided to $methodName(). The number of arguments must be less than or equal to the number of orderBy() clauses.');
    }

    final List<FieldValue> components = <FieldValue>[];
    for (int i = 0; i < values.length; i++) {
      final Object rawValue = values[i];
      final OrderBy orderBy = explicitOrderBy[i];
      if (orderBy.field == core.FieldPath.keyPath) {
        if (rawValue is! String) {
          throw ArgumentError(
              'Invalid query. Expected a string for document ID in $methodName(), but got $rawValue.');
        }
        final String documentId = rawValue;
        if (documentId.contains('/')) {
          throw ArgumentError(
              'Invalid query. Document ID "$documentId" contains a slash in $methodName()."');
        }
        final DocumentKey key =
            DocumentKey.fromPath(query.path.appendSegment(documentId));
        components.add(ReferenceValue.valueOf(firestore.databaseId, key));
      } else {
        final FieldValue wrapped =
            firestore.dataConverter.parseQueryValue(rawValue);
        components.add(wrapped);
      }
    }

    return Bound(components, before);
  }

  /// Executes the query and returns the results as a [QuerySnapshot].
  ///
  /// * By default, get() attempts to provide up-to-date data when possible by
  /// waiting for data from the server, but it may return cached data or fail if
  /// you are offline and the server cannot be reached. This behavior can be
  /// altered via the [Source] parameter.
  ///
  /// [source] a value to configure the get behavior.
  /// Returns a Future that will be resolved with the results of the [Query].
  @publicApi
  Future<QuerySnapshot> get([Source source = Source.DEFAULT]) async {
    if (source == Source.CACHE) {
      final ViewSnapshot viewSnap =
          await firestore.client.getDocumentsFromLocalCache(query);

      return QuerySnapshot(Query(query, firestore), viewSnap, firestore);
    } else {
      return getViaSnapshotListener(source);
    }
  }

  /*private*/
  Future<QuerySnapshot> getViaSnapshotListener(Source source) {
    final Completer<QuerySnapshot> res = Completer<QuerySnapshot>();
    final Completer<ListenerRegistration> registration =
        Completer<ListenerRegistration>();

    final ListenOptions options = ListenOptions();
    options.includeDocumentMetadataChanges = true;
    options.includeQueryMetadataChanges = true;
    options.waitForSyncWhenOnline = true;

    final ListenerRegistration listenerRegistration =
        addSnapshotListenerInternal(options,
            (QuerySnapshot snapshot, FirebaseFirestoreError error) async {
      if (error != null) {
        res.completeError(error);
        return;
      }

      try {
        // This await should be very short; we're just forcing synchronization
        // between this block and the outer registration.setResult.
        final ListenerRegistration actualRegistration =
            await registration.future;

        // Remove query first before passing event to user to avoid user actions
        // affecting the now stale query.
        actualRegistration.remove();

        if (snapshot.metadata.isFromCache && source == Source.SERVER) {
          res.completeError(FirebaseFirestoreError(
              'Failed to get documents from server. (However, these documents '
              'may exist in the local cache. Run again without setting source to SERVER to retrieve the cached documents.)',
              FirebaseFirestoreErrorCode.unavailable));
        } else {
          res.complete(snapshot);
        }
      } catch (e) {
        throw Assert.fail(
            'Failed to register a listener for a query result', e as Error);
      }
    });

    registration.complete(listenerRegistration);
    return res.future;
  }

  /// Starts listening to this query with the given options, using an Activity-scoped listener.
  ///
  /// * The listener will be automatically removed during {@link Activity#onStop}.
  ///
  /// @param activity The activity to scope the listener to.
  /// @param metadataChanges Indicates whether metadata-only changes (i.e. only {@code
  /// Query.getMetadata()} changed) should trigger snapshot events.
  /// @param listener The event listener that will be called with the snapshots.
  /// @return A registration object that can be used to remove the listener.
  @publicApi
  ListenerRegistration addSnapshotListener(
      EventListener<QuerySnapshot> listener,
      [MetadataChanges metadataChanges = MetadataChanges.EXCLUDE]) {
    Assert.checkNotNull(
        metadataChanges, 'Provided MetadataChanges value must not be null.');
    Assert.checkNotNull(listener, 'Provided EventListener must not be null.');
    return addSnapshotListenerInternal(
        internalOptions(metadataChanges), listener);
  }

  /// Internal helper method to create add a snapshot listener.
  ///
  /// todo update this once we have a way to integrate this with the widget system and onDispose
  /// * Will be Activity scoped if the activity parameter is non-null.
  ///
  /// @param options The options to use for this listen.
  /// @param listener The event listener that will be called with the snapshots.
  /// @return A registration object that can be used to remove the listener.
  /*private*/
  ListenerRegistration addSnapshotListenerInternal(
      ListenOptions options, EventListener<QuerySnapshot> listener) {
    void wrapperListener(ViewSnapshot snapshot, FirebaseFirestoreError error) {
      if (snapshot != null) {
        final QuerySnapshot querySnapshot =
            QuerySnapshot(this, snapshot, firestore);
        listener(querySnapshot, null);
      } else {
        Assert.hardAssert(
            error != null, 'Got event without value or error set');
        listener(null, error);
      }
    }

    final QueryListener queryListener =
        firestore.client.listen(query, options, wrapperListener);

    return ListenerRegistrationImpl(
      firestore.client,
      queryListener,
      ExecutorEventListener<ViewSnapshot>(wrapperListener),
    );
  }

  /// Converts the  API options object to the internal options object.
  /*private*/
  static ListenOptions internalOptions(MetadataChanges metadataChanges) {
    final ListenOptions internalOptions = ListenOptions();
    internalOptions.includeDocumentMetadataChanges =
        metadataChanges == MetadataChanges.INCLUDE;
    internalOptions.includeQueryMetadataChanges =
        metadataChanges == MetadataChanges.INCLUDE;
    internalOptions.waitForSyncWhenOnline = false;
    return internalOptions;
  }
}