// Firebase configuration and setup
import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';

// Firebase config
const firebaseConfig = {
  apiKey: "AIzaSyCKHrqvqJXqvqJXqvqJXqvqJXqvqJXqvqJ",
  authDomain: "juliaalgo-30369.firebaseapp.com",
  projectId: "juliaalgo-30369",
  storageBucket: "juliaalgo-30369.appspot.com",
  messagingSenderId: "112457008952333218417",
  appId: "1:112457008952333218417:web:123456789012345678"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Initialize Firebase Authentication and get a reference to the service
export const auth = getAuth(app);

// Initialize Cloud Firestore and get a reference to the service
export const db = getFirestore(app);

export default app;