## Create a firebase project in the browser

### Google account

You'll need a google account to use firebase. You can create one here:
https://www.google.com/account/about/

### Firebase Project

While logged in into your google account head over to:
https://firebase.google.com/

- Click on `Get started`
- Click on the plus sign with `add project`
- name your project and click on `continue`
- For now, we don't use google analytics (you can leave it enabled if you want to use it in the future)
- Click 'Create project'

### Adding a webapp to your project

in your project console (in the firebase project), we now want to add an app to our project

- Click on `</>`
- name the app (can be the same as your project) and check `Also set up Firebase Hosting`
- Click on `Register app`
- Click on `Next`
- Click on `Next`
- Click on `Continue to console`

### Adding Firestore to your project

in your project console in the left hand menu click on build and select Firestore Database

- Click on `Create database`
- Leave `Start in production mode` selected and click on `Next`
- Select a Firestore location and click on `Enable`
- To see if everything is set up correctly, in the menu click on the gear symbol next to the Project overview and
  select `Project settings`
- Under `Default GCP recource location` you should see the Firestore location, you've selected.
    - If you don't see the location, select one now (click on the `pencil-symbol` and then on `Done` in the pop-up
      window)

### Set up node

On your command line run:

```shell
node -v
```

If an error appears or the version number is bellow 16.0, install node. You can download the and install the newest
version here:
https://nodejs.org/

### Link the local project to the firebase project

Change the directory to the newly created folder

```shell
cd testing_zone
```

Login to firebase

```shell
firebase login
```

Initialize the project:

```shell
firebase init
```

In your command line a dialog should appear.

- Choose (by selecting and pressing space bar):
    - Firestore: Configure security rules and indexes files for Firestore
    - Hosting: Configure files for Firebase Hosting and (optionally) set up GitHub Action deploys
    - Press `Enter`
- Use an existing project -> `Enter`
- Select the project you created when creating the project in the browser -> `Enter`
- For Firestore Rules, leave the default -> `Enter`
- For Firestore indexes, leave the default -> `Enter`
- ATTENTION: For the public directory, type in `build` and press `Enter`
- Configure as single page app, type `y` and press `Enter`
- No automatic builds and deploys with GitHub, type `n` and press `Enter`

### Set the credentials
In the testing_zone folder there is a .env file, where you need to replace the default values with credentials from your Firebase Project.
You find the credentials in the Firebase Project under Project-Overview -> Project Settings.

```javascript
const firebaseConfig = {
  apiKey: "apiKey",
  authDomain: "authDomain",
  projectId: "projectId",
  storageBucket: "storageBucket",
  messagingSenderId: "messagingSenderId",
  appId: "appId",
  measurementId: "measurementId"
};
```

### Write your own code

Write your own code in the src/design/main.js folder.

### Test your experiment

you can test the experiment locally via

```shell
npm start
```

#### Attention: Testing without database

When running the experiment locally, by default the condition and id in your main function is set to 0. If you populated
your database already (for example with an autora-firebase-runner), you can use the conditions in your database by
setting the REACT_APP_devNoDb to False in the .env file.

### Build and deploy the experiment

#### Build

To build and deploy the experiment run

```shell
npm run build
```

This will create a new build folder in the test_subject_environment directory.

#### Deploy

To deploy the experiment, run

```shell
firebase deploy
```

This will deploy the experiment to firebase, and you will get a link where participants can access it.