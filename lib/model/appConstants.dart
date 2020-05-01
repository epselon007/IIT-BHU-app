import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iit_app/data/post_api_service.dart';
import 'package:iit_app/model/built_post.dart';
import 'package:iit_app/model/database_helpers.dart';
import 'package:built_collection/built_collection.dart';
import 'package:iit_app/services/connectivityCheck.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class AppConstants {
  //  connectivity variables ------------------------------------------

  static ConnectionStatusSingleton connectionStatus;
  static bool isLoggedIn = false;
  // static bool isOnline = false;
  // static Stream connectivityStream;

  // ------------------------------------------ connectivity variables

  static bool logInButtonEnabled = true;
  static bool firstTimeFetching = true;
  static bool refreshingHomePage = false;

  static String deviceDirectoryPath;

  static String djangoToken;

  static FirebaseUser currentUser;
  static PostApiService service;

  static BuiltList<BuiltWorkshopSummaryPost> workshopFromDatabase;

  // !-------------------------
  static BuiltList<BuiltAllCouncilsPost> councilsSummaryfromDatabase;
  // !-------------------------

  static int currentCouncilId;

  static Future populateWorkshopsAndCouncilButtons() async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    councilsSummaryfromDatabase =
        await helper.getAllCouncilsSummary(db: database);
    workshopFromDatabase = await helper.getAllWorkshopsSummary(db: database);

    // print(' workshops is empty: ${(workshops.isEmpty == true).toString()}');

    if (workshopFromDatabase == null) {
      // insert all workshop information for the first time
      await helper.deleteWorkshopsSummary(db: database);
      await helper.deleteAllCouncilsSummary(db: database);

      print('fetching workshops and all councils summary from json');

// API calls to fetch the data
      Response<BuiltList<BuiltWorkshopSummaryPost>> workshopSnapshots =
          await service.getActiveWorkshops();
      final workshopPosts = workshopSnapshots.body;

      Response<BuiltList<BuiltAllCouncilsPost>> councilSummarySnapshots =
          await service.getAllCouncils();
      final councilSummaryPosts = councilSummarySnapshots.body;

// storing the data fetched from json objects into local database
      // ? remember, we use council summary in database while fetching other data (most of time)
      for (var post in councilSummaryPosts) {
        await helper.insertCouncilSummaryIntoDatabase(councilSummary: post);
      }

      await writeCouncilLogosIntoDisk(councilSummaryPosts);

      for (var post in workshopPosts) {
        await helper.insertWorkshopSummaryIntoDatabase(post: post);
      }

// fetching the data from local database and storing it into variables
// whose scope is throughout the app

      councilsSummaryfromDatabase = councilSummaryPosts;
      // await helper.getAllCouncilsSummary(db: database);
      workshopFromDatabase = workshopPosts;
      // await helper.getAllWorkshopsSummary(db: database);

    }

    // helper.closeDatabase(db: database);
    print('workshops and all councils summary fetched ');
  }

  static Future writeCouncilLogosIntoDisk(
      BuiltList<BuiltAllCouncilsPost> councils) async {
    for (var council in councils) {
      final url = council.small_image_url;
      final response = await http.get(url);
      final imageData = response.bodyBytes.toList();
      final File file = File(
          '${AppConstants.deviceDirectoryPath}/council_${council.id}(small)');
      file.writeAsBytesSync(imageData);
    }
  }

// TODO: we fetch council summaries only once in while initializing empty database, make it refreshable.

  static Future updateAndPopulateWorkshops() async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    await helper.deleteWorkshopsSummary(db: database);

    print('fetching workshops infos from json for updation');

    Response<BuiltList<BuiltWorkshopSummaryPost>> workshopSnapshots =
        await service.getActiveWorkshops();

    final workshopPosts = workshopSnapshots.body;

    for (var post in workshopPosts) {
      await helper.insertWorkshopSummaryIntoDatabase(post: post);
    }
    workshopFromDatabase = workshopPosts;

    print('workshops fetched and updated ');

    // helper.closeDatabase(db: database);
  }

  static Future getCouncilDetailsFromDatabase({@required int councilId}) async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    BuiltCouncilPost councilPost =
        await helper.getCouncilDetail(db: database, councilId: councilId);

    if (councilPost == null) {
      Response<BuiltCouncilPost> councilSnapshots =
          await AppConstants.service.getCouncil(AppConstants.currentCouncilId);

      councilPost = councilSnapshots.body;

      await helper.insertCouncilDetailsIntoDatabase(councilPost: councilPost);
    }

    return councilPost;
  }

  static Future getAndUpdateCouncilDetailsInDatabase(
      {@required int councilId}) async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    print('deleting council entries ---------------------------');
    await helper.deleteEntryOfCouncilDetail(db: database, councilId: councilId);
    print('deleted ---------------------------');

    Response<BuiltCouncilPost> councilSnapshots =
        await AppConstants.service.getCouncil(councilId);

    var councilPost = councilSnapshots.body;

    await helper.insertCouncilDetailsIntoDatabase(councilPost: councilPost);

    return councilPost;
  }

  static Future getClubDetailsFromDatabase({@required int clubId}) async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    BuiltClubPost clubPost =
        await helper.getClubDetails(db: database, clubId: clubId);

    if (clubPost == null) {
      Response<BuiltClubPost> clubSnapshots = await AppConstants.service
          .getClub(clubId, "token ${AppConstants.djangoToken}")
          .catchError((onError) {
        print("Error in fetching clubs: ${onError.toString()}");
      });
      clubPost = clubSnapshots.body;

      await helper.insertClubDetailsIntoDatabase(clubPost: clubPost);
    }

    return clubPost;
  }

  static Future updateClubDetailsInDatabase(
      {@required BuiltClubPost clubPost}) async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

// here, we are not doing exactly like we did for council. because everytime we have to fetch workshops
// so  API request will be sent anyway. Therefore to ensure minimum requests, we will fetch all data altogether.
// Keep in mind: Use of local database is done to achieve quick fetching of club data except workshops

    await helper.deleteEntryOfClubDetail(db: database, clubId: clubPost.id);

    await helper.insertClubDetailsIntoDatabase(clubPost: clubPost);
  }

  static Future updateClubSubscriptionInDatabase(
      {@required int clubId,
      @required bool isSubscribed,
      @required int currentSubscribedUsers}) async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    final subscribedUsers = currentSubscribedUsers + (isSubscribed ? 1 : -1);

    await helper.updateClubSubcription(
        db: database,
        clubId: clubId,
        isSubscribed: isSubscribed,
        subscribedUsers: subscribedUsers);
  }
}
