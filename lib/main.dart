// import 'dart:html';
import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:snapping_sheet/snapping_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:ui' as ui;


enum Status {
  AuthenticatingLogin,
  AuthenticatingSignup,
  Unauthenticated,
  Authenticated
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(App());
}

class LoginNotifier extends ChangeNotifier {
  FirebaseAuth _auth = FirebaseAuth.instance;
  User? _user;
  Status _status = Status.Unauthenticated;

  List<String> _suggestionsFirst = [];
  List<String> _suggestionsSecond = [];

  FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FirebaseStorage _storage = FirebaseStorage.instance;


  FirebaseAuth get auth => _auth;

  Status get status => _status;

  set status(Status status) {
    _status = status;
    notifyListeners();
  }

  void setListsWithSaved(List<WordPair> _saved) {
    _suggestionsFirst..clear();
    _suggestionsSecond..clear();
    for (var i = 0; i < _saved.length; i++) {
      _suggestionsFirst.add(_saved[i].first);
      _suggestionsSecond.add(_saved[i].second);
    }
  }

  LoginNotifier() {
    _auth.authStateChanges().listen((User? firebaseUser) async {
      if (firebaseUser == null) {
        _user = null;
        _status = Status.Unauthenticated;
      } else {
        _user = firebaseUser;
        _status = Status.Authenticated;
      }
      notifyListeners();
    });
  }

  Future<void> addOrUpdateUserSuggestions(String email, List<WordPair> _saved,
      List suggestionsFirstCloud, List suggestionsSecondCloud) async {

    if(email.isEmpty || email == 'Email') {
      return;
    }

    List<String> suggestionsFirst = [];
    List<String> suggestionsSecond = [];
    List<WordPair> helper = [];

    for (var i = 0; i < suggestionsFirstCloud.length; i++) {
      helper.add(WordPair(suggestionsFirstCloud[i], suggestionsSecondCloud[i]));
      suggestionsFirst.add(suggestionsFirstCloud[i]);
      suggestionsSecond.add(suggestionsSecondCloud[i]);
    }

    for (var j = 0; j < _saved.length; j++) {
      if (helper.contains(_saved[j])) {
        continue;
      }
      suggestionsFirst.add(_saved[j].first);
      suggestionsSecond.add(_saved[j].second);
    }

    print('suggestionsFirst - addOrUpdate: $suggestionsFirst');
    print('suggestionsSecond - addOrUpdate: $suggestionsSecond');

    _suggestionsFirst = suggestionsFirst;
    _suggestionsSecond = suggestionsSecond;

    return _firestore.collection("users").doc(email).set({
      'suggestionsFirst': suggestionsFirst,
      'suggestionsSecond': suggestionsSecond,
      'last_updated_at': Timestamp.now()
    }).onError((e, _) => print("Error writing document: $e"));
  }

  Future<DocumentSnapshot> getUserSuggestions(String email) {
      return _firestore.collection('users').doc(email).get();
  }

  Future<bool> signIn(String email, String password) async {
    try {
      if (email.isEmpty ||
          password.isEmpty ||
          email == 'Email' ||
          password == 'Password') {
        return false;
      }
      _status = Status.AuthenticatingLogin;
      notifyListeners();
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return true;
    } catch (e) {
      print(e);
      _status = Status.Unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<UserCredential?> signUp(String email, String password) async {
    try {
      if (email.isEmpty ||
          password.isEmpty ||
          email == 'Email' ||
          password == 'Password') {
        return null;
      }
      _status = Status.AuthenticatingSignup;
      notifyListeners();
      return await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
    } catch (e) {
      print(e);
      _status = Status.Unauthenticated;
      notifyListeners();
      return null;
    }
  }

  Future<String?> uploadFile(String localPath, String cloudPath) async{
    var fileRef = _storage.ref().child(cloudPath);
    var file = File(localPath);
    try{
      var uploadTask = await fileRef.putFile(file);
      return uploadTask.ref.getDownloadURL();
    }
    catch(e){
      print("Problem with uploading the file");
      return null;
    }
  }
}

class App extends StatelessWidget {
  final Future<FirebaseApp> _initialization = Firebase.initializeApp();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
              body: Center(
                  child: Text(snapshot.error.toString(),
                      textDirection: TextDirection.ltr)));
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return MyApp();
        }
        return Center(child: CircularProgressIndicator());
      },
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => LoginNotifier(),
      child: MaterialApp(
        title: 'Startup Name Generator',
        theme: ThemeData(
            primarySwatch: Colors.deepPurple),
        home: const RandomWords(),
      ),
    );
  }
}

class RandomWords extends StatefulWidget {
  const RandomWords({Key? key}) : super(key: key);

  @override
  State<RandomWords> createState() => _RandomWordsState();
}

class _RandomWordsState extends State<RandomWords> {
  final _suggestions = <WordPair>[];
  final List<WordPair> _savedCloud = [];
  final _saved = <WordPair>{};
  final _biggerFont = const TextStyle(fontSize: 18);


  NetworkImage? profilePicCloud;
  var profilePicLocal;
  bool _isSnappingSheetOpen = false;
  double _blurLevel = 0.0;

  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();

  TextEditingController passwordVerificationController =
      TextEditingController();

  final snappingSheetController = SnappingSheetController();

  @override
  void dispose() {
    // Clean up the controller when the widget is removed from the
    // widget tree.
    emailController.dispose();
    passwordController.dispose();
    passwordVerificationController.dispose();

    super.dispose();
  }

  void _handleProfilePicUpdate() async{
    String cloudPath = "images/profile_pics/profile_${emailController.text}";
    final cloudPicRef = context.read<LoginNotifier>()._storage.ref().child(cloudPath);
    final profilePicCloudURL =  await cloudPicRef.getDownloadURL();
    setState((){
      profilePicLocal = null;
      profilePicCloud = NetworkImage(profilePicCloudURL);
    });
  }

  void _pushLogin() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          Status status = context.watch<LoginNotifier>().status;

          return Scaffold(
            appBar: AppBar(
              title: const Text('Login'),
            ),
            body: Padding(
              padding: const EdgeInsets.all(10),
              child: ListView(
                children: <Widget>[
                  Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(10),
                      child: const Text(
                        'Welcome to Startup Names Generator, please log in!',
                        style: TextStyle(fontSize: 15),
                      )),
                  Container(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Email',
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      obscureText: true,
                      controller: passwordController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Password',
                      ),
                    ),
                  ),
                  Container(
                      height: 50,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                      child: ElevatedButton(
                        child: (status == Status.AuthenticatingLogin)
                            ? const CircularProgressIndicator()
                            : const Text('login'),
                        onPressed: status == Status.AuthenticatingLogin
                            ? null
                            : () async {
                                Future<bool> signInRes = context .read<LoginNotifier>().signIn(emailController.text,passwordController.text);
                                bool signInResBool = await signInRes;
                                if (signInResBool == true) {
                                  // context.read<LoginNotifier>().status = Status.Authenticated;
                                  Future<DocumentSnapshot> futureDoc = context.read<LoginNotifier>().getUserSuggestions(emailController.text);
                                  DocumentSnapshot doc = await futureDoc;
                                  List currSuggestionsFirst = doc?.get('suggestionsFirst');

                                  // Handle profile pic
                                  String cloudPath = "images/profile_pics/profile_${emailController.text}";
                                  final cloudPicRef = context.read<LoginNotifier>()._storage.ref().child(cloudPath);
                                  final profilePicCloudURL =  await cloudPicRef.getDownloadURL();
                                  setState((){
                                    profilePicLocal = null;
                                    profilePicCloud = NetworkImage(profilePicCloudURL);
                                  });

                                  // get back to the main page
                                  Navigator.pop(context);


                                  //update the user favorites list on the cloud
                                  List currSuggestionsSecond = doc?.get('suggestionsSecond');
                                  // Future<void> newDocRes = context.read<LoginNotifier>().addOrUpdateUserSuggestions(emailController.text, _saved.toList(), currSuggestionsFirst, currSuggestionsSecond);
                                  await context.read<LoginNotifier>().addOrUpdateUserSuggestions(emailController.text, _saved.toList(), currSuggestionsFirst, currSuggestionsSecond);

                                } else {
                                  const loginErrorSnackBar = SnackBar(
                                      content: Text(
                                          'There was an error logging into the app'));
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(loginErrorSnackBar);
                                }
                              },
                      )),
                  Container(
                      height: 50,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan,
                        ),
                        child: (status == Status.AuthenticatingSignup)
                            ? const CircularProgressIndicator()
                            : const Text('New user? Click to sign up'),
                        onPressed: (status == Status.AuthenticatingSignup)
                            ? null
                            : () async {
                          var completedAuth = false;
                                // Future<void> showModalBottomSheetFuture = showModalBottomSheet<void>(
                                await showModalBottomSheet(
                                  isScrollControlled: true,
                                  context: context,
                                  builder: (BuildContext context) {
                                    bool confirmedAuth = true;
                                    return StatefulBuilder(
                                        builder: (BuildContext context, StateSetter setStateModal){
                                          // we set up a container inside which
                                          // we create center column and display text

                                          // Returning SizedBox instead of a Container
                                          return Padding(
                                            padding: EdgeInsets.only(
                                                bottom: MediaQuery.of(context).viewInsets.bottom
                                            ),
                                            child: SizedBox(
                                              height:MediaQuery.of(context).size.height/4,
                                              child: Center(
                                                child: Column(
                                                  mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                                  children: <Widget>[
                                                    Text(
                                                        'Please confirm your password below:'),
                                                    Container(
                                                      padding: const EdgeInsets.all(10),
                                                      child: TextField(
                                                        obscureText: true,
                                                        controller:
                                                        passwordVerificationController,
                                                        decoration:
                                                        InputDecoration(
                                                          border: OutlineInputBorder(),
                                                          labelText: 'Password',
                                                          errorText: confirmedAuth ? null : 'Passwords must match',
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      height: 50,
                                                      padding: EdgeInsets.fromLTRB((3 / 8) * MediaQuery.of(context).size.width, 0, (3 / 8) * MediaQuery.of(context).size.width, 0),
                                                      child: ElevatedButton(
                                                          child: Text('Confirm'),
                                                          onPressed: () {
                                                            if(passwordController.text == passwordVerificationController.text){
                                                              //TODO: find out what to do when verification failed

                                                              setStateModal((){
                                                                confirmedAuth = true;
                                                              });
                                                              completedAuth = true;
                                                              print('Authentication completed');
                                                              Navigator.pop(context);
                                                            }
                                                            else {
                                                              setStateModal((){
                                                                confirmedAuth = false;
                                                              });
                                                              print('Authentication failed');
                                                            }
                                                          }
                                                      ),
                                                    )
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                    );
                                  },
                                );

                                print('completedAuth: $completedAuth');
                                if(!completedAuth){
                                  return;
                                }
                                // print("passwordController.text: ${passwordController.text}");
                                // print("passwordVerificationController.text: ${passwordVerificationController.text}");
                                // while(!completedAuth){} // wait until confirm screen is closed
                                if(passwordController.text != passwordVerificationController.text){
                                  //TODO: find out what to do when verification failed
                                  print('authentication failed');
                                  return;
                                }
                                print('authentication successful');
                                // return;

                                Future<UserCredential?> signUpRes = context
                                    .read<LoginNotifier>()
                                    .signUp(emailController.text,
                                        passwordController.text);
                                // Future<void> newDocRes = context.read<LoginNotifier>().addOrUpdateUserSuggestions(emailController.text, _saved.toList());

                                UserCredential? signInRes = await signUpRes;
                                if (signInRes != null) {
                                  setState((){
                                    profilePicLocal = null;
                                    profilePicCloud = null;
                                  });

                                  Navigator.pop(context); // get back to previous page
                                  Future<void> newDocRes = context
                                      .read<LoginNotifier>()
                                      .addOrUpdateUserSuggestions(
                                          emailController.text,
                                          _saved.toList(), [], []);
                                  await newDocRes;
                                } else {
                                  const signupErrorSnackBar = SnackBar(
                                      content: Text(
                                          'There was an error signing up into the app'));

                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(signupErrorSnackBar);
                                }
                              },
                      )),
                ],
              ),
            ),
          );
        },
      ), // ...to here.
    );
  }

//builder here so that we show database info instead of _saved
  void _pushSaved() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          final tilesNoUser = _saved.map(
            (pair) {
              return Dismissible(
                key: Key('key: $pair'),
                direction: DismissDirection.horizontal,
                background: Row(
                  children: const <Widget>[
                    Icon(Icons.delete),
                    Padding(
                        padding: EdgeInsets.all(10),
                        child: Text('Delete suggestion'))
                  ],
                ),
                confirmDismiss: (DismissDirection direction) async {
                  return await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text("Delete Suggestion"),
                        content: Text(
                            'Are you sure you wish to delete ${pair.asPascalCase} from your saved suggestions?'),
                        actions: <Widget>[
                          ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop(true);
                                setState(() {
                                  _saved.remove(pair);
                                });
                              },
                              child: const Text("Yes")),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text("No"),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: ListTile(
                  title: Text(
                    pair.asPascalCase,
                    style: _biggerFont,
                  ),
                ),
              );
            },
          );
          final dividedNoUser = tilesNoUser.isNotEmpty
              ? ListTile.divideTiles(
                  context: context,
                  tiles: tilesNoUser,
                ).toList()
              : <Widget>[];

          final tilesUser = _savedCloud.map(
            (pair) {
              return Dismissible(
                key: Key('key: $pair'),
                direction: DismissDirection.horizontal,
                background: Row(
                  children: const <Widget>[
                    Icon(Icons.delete),
                    Padding(
                        padding: EdgeInsets.all(10),
                        child: Text('Delete suggestion'))
                  ],
                ),
                confirmDismiss: (DismissDirection direction) async {
                  return await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text("Delete Suggestion"),
                        content: Text(
                            'Are you sure you wish to delete ${pair.asPascalCase} from your saved suggestions?'),
                        actions: <Widget>[
                          ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop(true);
                                setState(() {
                                  _savedCloud.remove(pair);
                                });
                                context
                                    .read<LoginNotifier>()
                                    .setListsWithSaved(_savedCloud);
                                context
                                    .read<LoginNotifier>()
                                    .addOrUpdateUserSuggestions(
                                        emailController.text,
                                        _savedCloud.toList(), [], []);
                                print('$_savedCloud after deleting $pair');
                              },
                              child: const Text("Yes")),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text("No"),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: ListTile(
                  title: Text(
                    pair.asPascalCase,
                    style: _biggerFont,
                  ),
                ),
              );
            },
          );
          final dividedUser = tilesUser.isNotEmpty
              ? ListTile.divideTiles(
                  context: context,
                  tiles: tilesUser,
                ).toList()
              : <Widget>[];

          return (context.read<LoginNotifier>().status ==
                  Status.Unauthenticated)
              ? Scaffold(
                  appBar: AppBar(
                    title: const Text('Saved Suggestions'),
                  ),
                  body: ListView(children: dividedNoUser),
                )
              : Scaffold(
                  appBar: AppBar(
                    title: const Text('Saved Suggestions'),
                  ),
                  body: ListView(children: dividedUser),
                );
        },
      ), // ...to here.
    );
  }

  void _logOut() async {
    await context.read<LoginNotifier>().auth.signOut();
    const logOutSnackBar = SnackBar(content: Text('Successfully logged out'));

    ScaffoldMessenger.of(context).showSnackBar(logOutSnackBar);
  }

  @override
  Widget build(BuildContext context) {
    Status status = context.watch<LoginNotifier>().status;
    var appBarActions;
    if (status != Status.Authenticated) {
      appBarActions = [
        IconButton(
          icon: const Icon(Icons.star),
          onPressed: _pushSaved,
          tooltip: 'Saved Suggestions',
        ),
        IconButton(
          icon: const Icon(Icons.login),
          onPressed: _pushLogin,
          tooltip: 'Login Screen',
        ),
      ];
    } else {
      appBarActions = [
        IconButton(
          icon: const Icon(Icons.star),
          onPressed: _pushSaved,
          tooltip: 'Saved Suggestions',
        ),
        IconButton(
          icon: const Icon(Icons.exit_to_app),
          onPressed:
              _logOut, //TODO: update handler//await FirebaseAuth.instance.signOut();
          tooltip: 'exit',
        )
      ];
    }
    // final Future<DocumentSnapshot> _getDoc = context.read<LoginNotifier>().getUserSuggestions(emailController.text);
    final ListView listView = ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemBuilder: (context, i) {
        if (i.isOdd) return const Divider();

        final index = i ~/ 2;
        if (index >= _suggestions.length) {
          _suggestions.addAll(generateWordPairs().take(10));
        }
        final alreadySaved = _saved.contains(_suggestions[index]);
        // final Future<DocumentSnapshot> _getDoc = context.read<LoginNotifier>().getUserSuggestions(emailController.text);
        return (status == Status.Unauthenticated)
            ? ListTile(
                title: Text(
                  _suggestions[index].asPascalCase,
                  style: _biggerFont,
                ),
                trailing: Icon(
                  alreadySaved ? Icons.favorite : Icons.favorite_border,
                  color: alreadySaved ? Colors.red : null,
                  semanticLabel: alreadySaved ? 'Remove from saved' : 'Save',
                ),
                onTap: () {
                  setState(() {
                    if (alreadySaved) {
                      _saved.remove(_suggestions[index]);
                    } else {
                      _saved.add(_suggestions[index]);
                    }
                  });
                },
              )
            :
            //FutureBuilder and ListTile for connected users
            FutureBuilder<DocumentSnapshot>(
                future: context
                    .read<LoginNotifier>()
                    .getUserSuggestions(emailController.text).catchError((e){
                      setState(() {
                        context.read<LoginNotifier>().status = Status.Unauthenticated;
                      });
                }),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    status = Status.Authenticated;
                    // List suggestionsFirstCloud = snapshot.data?['suggestionsFirst'] ?? [];
                    // List suggestionsSecondCloud = snapshot.data?['suggestionsSecond'] ?? [];
                    List suggestionsFirstCloud =
                        context.read<LoginNotifier>()._suggestionsFirst;
                    List suggestionsSecondCloud =
                        context.read<LoginNotifier>()._suggestionsSecond;
                    _savedCloud..clear();

                    for (var i = 0; i < suggestionsFirstCloud.length; i++) {
                      _savedCloud.add(WordPair(
                          suggestionsFirstCloud[i], suggestionsSecondCloud[i]));
                      print('suggestionsFirst $i : $suggestionsFirstCloud');
                      print('suggestionsSecond $i : $suggestionsSecondCloud');
                    }

                    final alreadySavedCloud =
                        _savedCloud.contains(_suggestions[index]);
                    return ListTile(
                      title: Text(
                        _suggestions[index].asPascalCase,
                        style: _biggerFont,
                      ),
                      trailing: Icon(
                        alreadySavedCloud
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: alreadySavedCloud ? Colors.red : null,
                        semanticLabel:
                            alreadySavedCloud ? 'Remove from saved' : 'Save',
                      ),
                      onTap: () {
                        setState(() {
                          if (alreadySavedCloud) {
                            _savedCloud.remove(_suggestions[index]);
                          } else {
                            _savedCloud.add(_suggestions[index]);
                          }
                        });
                        context
                            .read<LoginNotifier>()
                            .addOrUpdateUserSuggestions(emailController.text,
                                _savedCloud.toList(), [], []);
                      },
                    );
                  } else {
                    // return ListTile(
                    // title: Text('An error from line: ${StackTrace.current}')
                    // );
                    // return CircularProgressIndicator();
                    final alreadySavedCloud =
                        _savedCloud.contains(_suggestions[index]);
                    return ListTile(
                      title: Text(
                        _suggestions[index].asPascalCase,
                        style: _biggerFont,
                      ),
                      trailing: Icon(
                        alreadySavedCloud
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: alreadySavedCloud ? Colors.red : null,
                        semanticLabel:
                            alreadySavedCloud ? 'Remove from saved' : 'Save',
                      ),
                      onTap: () {
                        setState(() {
                          if (alreadySavedCloud) {
                            _savedCloud.remove(_suggestions[index]);
                          } else {
                            _savedCloud.add(_suggestions[index]);
                          }
                        });
                        context
                            .read<LoginNotifier>()
                            .addOrUpdateUserSuggestions(emailController.text,
                                _savedCloud.toList(), [], []);
                      },
                    );
                  }
                });
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Startup Name Generator'),
        actions: appBarActions,
      ),
      body: status != Status.Authenticated
          ? listView
          : SnappingSheet(
              lockOverflowDrag: true,
              controller: snappingSheetController,
              onSheetMoved: (sheetPosition){
                setState(() {
                  _blurLevel = sheetPosition.relativeToSnappingPositions * 8;
                });
              },
              snappingPositions: [
                SnappingPosition.factor(
                  positionFactor: 0.0,
                  grabbingContentOffset: GrabbingContentOffset.top,
                ),
                SnappingPosition.factor(
                  snappingCurve: Curves.elasticOut,
                  snappingDuration: Duration(milliseconds: 1750),
                  positionFactor: 0.2,
                ),
                SnappingPosition.factor(positionFactor: 0.7),
              ],
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  listView
                ] + ((_blurLevel > 0) ?
                <Widget>[BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: _blurLevel,
                    sigmaY: _blurLevel,
                  ),
                  child: Container(
                    color: Colors.transparent,
                  ),
                )] :
                    <Widget>[])
                ,
              ),
              grabbingHeight: 50,
              grabbing: GestureDetector(
                onTap: () {
                  if(snappingSheetController.isAttached) {
                    print('I was Tapped!');
                    if (snappingSheetController.currentSnappingPosition ==
                        SnappingPosition.factor(
                          snappingCurve: Curves.elasticOut,
                          snappingDuration: Duration(milliseconds: 1750),
                          positionFactor: 0.2,
                        )) {
                      snappingSheetController.snapToPosition(
                          SnappingPosition.factor(
                            positionFactor: 0.0,
                            grabbingContentOffset: GrabbingContentOffset.top,
                          ));
                    } else {
                      snappingSheetController.snapToPosition(
                          SnappingPosition.factor(
                            snappingCurve: Curves.elasticOut,
                            snappingDuration: Duration(milliseconds: 1750),
                            positionFactor: 0.2,
                          ));
                    }
                  }
                },
                child: Container(
                  color: Colors.grey.shade300,
                  child: ListTile(
                    title: Text(
                      'Welcome back, ${emailController.text}',
                      style: TextStyle(fontSize: 15),
                    ),
                    trailing: Icon(Icons.keyboard_arrow_up),
                  ),
                ),
              ),
              sheetBelow: SnappingSheetContent(
                // childScrollController: _scrollController,
                draggable: true,
                child: Container(
                    // height: 50,
                    // width: 50,
                    color: Colors.white,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage: (profilePicCloud == null) ? profilePicLocal : profilePicCloud,
                        // backgroundImage: profilePicLocal,
                        // backgroundImage: AssetImage("assets/profilePic.jpg"),
                        backgroundColor: Colors.white,
                      ),
                      title: Text(
                        '${emailController.text}',
                        style: _biggerFont,
                      ),
                      subtitle: Container(
                          padding: EdgeInsets.fromLTRB(0, 5,
                              2 * MediaQuery.of(context).size.width / 5, 5),
                          // width: MediaQuery.of(context).size.width/4,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyan,
                            ),
                            child: Text('Change Avatar'),
                            onPressed: () async {

                              final result = await FilePicker.platform.pickFiles();
                              if(result == null){
                                const noImagePickedSnackBar = SnackBar(
                                    content: Text('No image selected'));
                                ScaffoldMessenger.of(context).showSnackBar(noImagePickedSnackBar);
                                return;
                              }
                              if(result?.paths.length != 1){
                                const multipleImagesPickedSnackBar = SnackBar(
                                    content: Text('Please pick only one image'));
                                ScaffoldMessenger.of(context).showSnackBar(multipleImagesPickedSnackBar);
                                return;
                              }

                              String? localPath = result.paths[0];
                              // profilePicLocal = Image.file(File(localPath!)).image;
                              String cloudPath = "images/profile_pics/profile_${emailController.text}";

                              setState((){
                                profilePicLocal = Image.file(File(localPath!)).image;
                                profilePicCloud = null;
                              });

                              await context.read<LoginNotifier>().uploadFile(localPath!, cloudPath);

                            },

                          )),
                    )),
              ),
            ),
    );
  }
}
