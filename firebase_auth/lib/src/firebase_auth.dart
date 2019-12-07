// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth;

///  The maximum wait time before attempting to retry auto refreshing tokens after a failed attempt.
///
/// This is the upper limit of the exponential backoff used for retrying token refresh.
const Duration _kMaxWaitTimeForBackoff = Duration(minutes: 16);

/// The amount of time before the token expires that proactive refresh should be attempted.
const Duration _kTokenRefreshHeadStart = Duration(minutes: 5);

class FirebaseAuth implements InternalTokenProvider {
  FirebaseAuth._(this._app, this._firebaseAuthApi, this._configuration, this._userStorage)
      : _platformDependencies = _app.platformDependencies;

  factory FirebaseAuth.getInstance(FirebaseApp app) {
    _authStateChangedSubjects[FirebaseApp.instance.name] = BehaviorSubject<FirebaseUser>();

    final AuthRequestConfiguration configuration =
        AuthRequestConfiguration(apiKey: app.options.apiKey, languageCode: app.platformDependencies.locale);

    final HttpService identityToolkitService =
        HttpService(configuration: configuration, host: 'https://www.googleapis.com/identitytoolkit/v3/relyingparty');

    final FirebaseAuthApi firebaseAuthApi =
        FirebaseAuthApi(firebaseAuthService: FirebaseAuthService(service: identityToolkitService));

    final UserStorage userStorage = UserStorage(userBox: app.platformDependencies.box, appName: app.name);
    final FirebaseAuth auth = FirebaseAuth._(app, firebaseAuthApi, configuration, userStorage);
    final FirebaseUser user = userStorage.get(auth);
    auth
      .._updateCurrentUser(user, saveToDisk: false)
      .._lastNotifiedUserToken = user?._rawAccessToken;

    return _instances[FirebaseApp.instance.name] = auth;
  }

  // ignore: prefer_constructors_over_static_methods
  static FirebaseAuth get instance {
    if (_instances.containsKey(FirebaseApp.instance.name)) {
      return _instances[FirebaseApp.instance.name];
    } else {
      final FirebaseAuth auth = FirebaseAuth.getInstance(FirebaseApp.instance);
      _instances[FirebaseApp.instance.name] = auth;
      return auth;
    }
  }

  final FirebaseApp _app;
  final FirebaseAuthApi _firebaseAuthApi;
  final UserStorage _userStorage;
  final AuthRequestConfiguration _configuration;
  final PlatformDependencies _platformDependencies;

  StreamSubscription<bool> _backgroundChangedSub;
  bool _isAppInBackground;

  FirebaseUser _currentUser;
  String _lastNotifiedUserToken;
  bool _autoRefreshTokens = false;
  bool _autoRefreshScheduled = false;

  static final Map<String, FirebaseAuth> _instances = <String, FirebaseAuth>{};
  static final Map<String, BehaviorSubject<FirebaseUser>> _authStateChangedSubjects =
      <String, BehaviorSubject<FirebaseUser>>{};

  /// Receive [FirebaseUser] each time the user signIn or signOut
  Stream<FirebaseUser> get onAuthStateChanged {
    return _authStateChangedSubjects[_app.name];
  }

  /// Asynchronously creates and becomes an anonymous user.
  ///
  /// If there is already an anonymous user signed in, that user will be
  /// returned instead. If there is any other existing user signed in, that
  /// user will be signed out.
  ///
  /// **Important**: You must enable Anonymous accounts in the Auth section
  /// of the Firebase console before being able to use them.
  ///
  /// Errors:
  ///   • [FirebaseAuthError.operationNotAllowed] - Indicates that Anonymous accounts are not enabled.
  Future<AuthResult> signInAnonymously() async {
    if (_currentUser != null && _currentUser.isAnonymous) {
      return _ensureUserPersistence(AuthResult._(_currentUser));
    }

    final BaseAuthRequest request = BaseAuthRequest();
    final BaseAuthResponse response = await _firebaseAuthApi.signUpNewUser(request);

    final FirebaseUser user = await _completeSignInWithAccessToken(
        response.idToken, response.expiresIn, response.refreshToken,
        anonymous: true);

    return _ensureUserPersistence(AuthResult._(user, AdditionalUserInfoImpl.newAnonymous()));
  }

  /// Tries to create a new user account with the given email address and password.
  ///
  /// If successful, it also signs the user in into the app and updates
  /// the [onAuthStateChanged] stream.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.invalidEmail] - Indicates the email address is malformed.
  ///   * [FirebaseAuthError.emailAlreadyInUse] - Indicates the email used to attempt sign up already exists. Call
  ///     [fetchProvidersForEmail] to check which sign-in mechanisms the user used, and prompt the user to sign in with
  ///     one of those.
  ///   * [FirebaseAuthError.operationNotAllowed] -  Indicates that email and password accounts are not enabled. Enable
  ///     them in the Auth section of the Firebase console.
  ///   * [FirebaseAuthError.weakPassword] - Indicates an attempt to set a password that is considered too weak.
  Future<AuthResult> createUserWithEmailAndPassword({@required String email, @required String password}) async {
    assert(email != null);
    assert(password != null);

    final BaseAuthRequest request = BaseAuthRequest(email: email, password: password);
    final BaseAuthResponse response = await _firebaseAuthApi.signUpNewUser(request);

    final FirebaseUser user =
        await _completeSignInWithAccessToken(response.idToken, response.expiresIn, response.refreshToken);
    final AdditionalUserInfoImpl additionalUserInfo =
        AdditionalUserInfoImpl(providerId: ProviderType.password, isNewUser: true);

    return AuthResult._(user, additionalUserInfo);
  }

  /// Returns a list of sign-in methods that can be used to sign in a given user (identified by its main email address).
  ///
  /// This method is useful when you support multiple authentication mechanisms if you want to implement an email-first
  /// authentication flow.
  ///
  /// An empty `List` is returned if the user could not be found.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.invalidEmail] - If the [email] address is malformed.
  Future<List<String>> fetchSignInMethodsForEmail({@required String email}) async {
    assert(email != null);

    final CreateAuthUriRequest request = CreateAuthUriRequest(identifier: email, continueUri: 'http://www.google.com/');
    final CreateAuthUriResponse response = await _firebaseAuthApi.createAuthUri(request);

    return response.registered ? response.allProviders.toList() : <String>[];
  }

  /// Triggers the Firebase Authentication backend to send a password-reset email to the given email address, which must
  /// correspond to an existing user of your app.
  ///
  /// Errors:
  ///  * [FirebaseAuthError.invalidRecipientEmail] - Indicates an invalid recipient email was sent in the request.
  ///  * [FirebaseAuthError.invalidSender] - Indicates an invalid sender email is set in the console for this action.
  ///  * [FirebaseAuthError.invalidMessagePayload] - Indicates an invalid email template for sending update email.
  ///  * [FirebaseAuthError.missingIosBundleID] - Indicates that the iOS bundle ID is missing when
  ///    [ActionCodeSettings.handleCodeInApp] is set to true.
  ///  * [FirebaseAuthError.missingAndroidPackageName] - Indicates that the android package name is missing when the
  ///    [ActionCodeSettings.androidInstallApp] flag is set to true.
  ///  * [FirebaseAuthError.unauthorizedDomain] - Indicates that the domain specified in the continue URL is not
  ///    whitelisted in the Firebase console.
  ///  * [FirebaseAuthError.invalidContinueURI] - Indicates that the domain specified in the continue URI is not valid.
  ///  * [FirebaseAuthError.userNotFound] - Indicates that there is no user corresponding to the given [email] address.
  Future<void> sendPasswordResetEmail({@required String email, ActionCodeSettings settings}) async {
    assert(email != null);

    final OobCodeRequest request = OobCodeRequest.resetPassword(email: email, settings: settings);
    return _firebaseAuthApi._firebaseAuthService.sendOobCode(request);
  }

  /// Sends a sign in with email link to provided email address.
  Future<void> sendSignInWithEmailLink({@required String email, @required ActionCodeSettings settings}) async {
    assert(email != null);
    assert(settings != null);

    final OobCodeRequest request = OobCodeRequest.emailLink(email: email, settings: settings);
    return _firebaseAuthApi._firebaseAuthService.sendOobCode(request);
  }

  /// Checks if link is an email sign-in link.
  bool isSignInWithEmailLink(String link) {
    if (link == null || link.isEmpty) {
      return false;
    }

    final Uri uri = Uri.tryParse(link);
    if (uri == null) {
      return false;
    }

    final Map<String, String> params = uri.queryParameters;
    if (params.isEmpty) {
      return false;
    }

    return params.containsKey('oobCode') && params['mode'] == 'signIn';
  }

  /// Signs in using an email address and email sign-in link.
  ///
  /// Errors:
  ///  * [FirebaseAuthError.operationNotAllowed] - Indicates that email and email sign-in link accounts are not enabled.
  ///    Enable them in the Auth section of the Firebase console.
  ///  * [FirebaseAuthError.userDisabled] - Indicates the user's account is disabled.
  ///  * [FirebaseAuthError.invalidEmail] - Indicates the email address is invalid.
  Future<AuthResult> signInWithEmailAndLink({String email, String link}) async {
    assert(email != null);
    assert(link != null);

    final EmailPasswordAuthCredential credential = EmailPasswordAuthCredential.withLink(email: email, link: link);
    final AuthResult result = await _signInAndRetrieveData(credential, isReauthentication: false);

    _updateCurrentUser(result.user, saveToDisk: true);
    return result;
  }

  /// Gets the cached current user, or null if there is none.
  FirebaseUser get currentUser => _currentUser;

  /// Signs in Firebase with the given 3rd party credentials (e.g. a Facebook login Access Token, a Google ID
  /// Token/Access Token pair, etc.) and returns additional identity provider data.
  Future<AuthResult> _signInAndRetrieveData(AuthCredential credential, {@required bool isReauthentication}) {
    if (credential is EmailPasswordAuthCredential) {
      if (credential.link != null) {
        return _signInAndRetrieveDataEmailAndLink(credential.email, credential.link);
      } else {
        //
      }
    }
  }

  Future<AuthResult> _signInAndRetrieveDataEmailAndLink(String email, String link) {
    assert(email != null && email.isNotEmpty);
    assert(link != null && link.isNotEmpty);

    final Uri uri = Uri.parse(link);
    final Map<String, String> params = uri.queryParameters;










  }

  /// Completes a sign-in flow once we have [accessToken] and [refreshToken] for the user.
  Future<FirebaseUser> _completeSignInWithAccessToken(String accessToken, int expiresIn, String refreshToken,
      {bool anonymous = false}) async {
    final DateTime accessTokenExpirationDate = DateTime.now().add(Duration(seconds: expiresIn)).toUtc();
    final FirebaseUser user = await FirebaseUser._retrieveUserWithAuth(
      this,
      accessToken,
      accessTokenExpirationDate,
      refreshToken,
      anonymous: anonymous,
    );
    _updateCurrentUser(user, saveToDisk: true);
    return user;
  }

  /// Force signs out the current user.
  void _signOutByForce(String uid) {
    if (_currentUser.uid != uid) {
      return;
    }

    _updateCurrentUser(null, saveToDisk: true);
  }

  /// Updates the store for the given user.
  void _updateStore(FirebaseUser user) {
    if (_currentUser != user) {
      // No-op if the user is no longer signed in. This is not considered an error as we don't check
      // whether the user is still current on other callbacks of user operations either.
      return;
    }

    _userStorage.save(user);
    _possiblyPostAuthStateChangeNotification();
  }

  AuthResult _ensureUserPersistence(AuthResult result) {
    _updateCurrentUser(result.user, saveToDisk: true);
    return result;
  }

  /// This method is called during: sign in and sign out events, as well as during class initialization time.
  ///
  /// The only time the [saveToDisk] parameter should be set to NO is during class initialization time because the user
  /// was just read from disk.
  void _updateCurrentUser(FirebaseUser user, {@required bool saveToDisk}) {
    if (user == _currentUser) {
      _possiblyPostAuthStateChangeNotification();
      return;
    }

    if (saveToDisk) {
      _userStorage.save(user);
    }

    _currentUser = user;
    _possiblyPostAuthStateChangeNotification();
  }

  void _possiblyPostAuthStateChangeNotification() {
    final String token = _currentUser?._rawAccessToken;
    if (_lastNotifiedUserToken == token || (token != null && _lastNotifiedUserToken == token)) {
      return;
    }
    _lastNotifiedUserToken = token;
    if (_autoRefreshTokens) {
      // Schedule new refresh task after successful attempt.
      _scheduleAutoTokenRefresh();
    }

    _dispatchUser(_currentUser);
  }

  /// Schedules a task to automatically refresh tokens on the current user.
  ///
  /// The token refresh is scheduled 5 minutes before the scheduled expiration time.
  void _scheduleAutoTokenRefresh() {
    final DateTime preExpirationDate = _currentUser._accessTokenExpirationDate.subtract(_kTokenRefreshHeadStart);
    Duration tokenExpirationInterval = preExpirationDate.difference(DateTime.now());
    tokenExpirationInterval = tokenExpirationInterval < Duration.zero ? Duration.zero : tokenExpirationInterval;
    _scheduleAutoTokenRefreshWithDelay(tokenExpirationInterval, false);
  }

  /// Schedules a task to automatically refresh tokens on the current user.
  Future<void> _scheduleAutoTokenRefreshWithDelay(Duration delay, bool retry) async {
    final String accessToken = _currentUser._rawAccessToken;
    if (accessToken == null) {
      return;
    }

    if (retry) {
      print('Token auto-refresh re-scheduled in $delay because of error on previous refresh attempt.');
    } else {
      print('Token auto-refresh scheduled in $delay for the new token.');
    }
    _autoRefreshScheduled = true;

    Timer(delay, () async {
      if (_currentUser._rawAccessToken != accessToken) {
        // Another auto refresh must have been scheduled so keep _autoRefreshScheduled unchanged.
        return;
      }
      _autoRefreshScheduled = false;
      if (_isAppInBackground) {
        return;
      }

      try {
        final String uid = _currentUser?.uid;
        await _currentUser._getToken(forceRefresh: true);

        if (_currentUser.uid != uid) {
          return;
        }
      } catch (e) {
        // Kicks off exponential back off logic to retry failed attempt. Starts with one minute delay (60 seconds) if
        // this is the first failed attempt.
        Duration rescheduleDelay;
        if (retry) {
          final Duration nextDelay = delay * 2;
          rescheduleDelay = nextDelay < _kMaxWaitTimeForBackoff ? nextDelay : _kMaxWaitTimeForBackoff;
        } else {
          rescheduleDelay = const Duration(minutes: 1);
        }
        await _scheduleAutoTokenRefreshWithDelay(rescheduleDelay, true);
      }
    });
  }

  void _dispatchUser(FirebaseUser user) {
    _authStateChangedSubjects[_app.name].add(user);
  }

  @override
  Future<GetTokenResult> getAccessToken({bool forceRefresh = false}) async {
    if (!_autoRefreshTokens) {
      print('Token auto-refresh enabled.');
      _autoRefreshTokens = true;
      _scheduleAutoTokenRefresh();

      _backgroundChangedSub = _platformDependencies.isBackgroundChanged.listen(_backgroundStateChanged);
    }

    if (_currentUser == null) {
      return null;
    }

    final String token = await _currentUser._getToken(forceRefresh: forceRefresh);
    return GetTokenResult(token);
  }

  @override
  String get uid => _currentUser?.uid;

  @override
  Stream<InternalTokenResult> get onTokenChanged {
    return onAuthStateChanged.map((FirebaseUser user) => InternalTokenResult(user?.refreshToken));
  }

  void _backgroundStateChanged(bool isBackground) {
    _isAppInBackground = isBackground;
    if (!isBackground && !_autoRefreshScheduled) {
      _scheduleAutoTokenRefresh();
    }
  }
}
