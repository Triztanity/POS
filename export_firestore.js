const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase with your project
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id,
});

const db = admin.firestore();

async function exportCollection(collectionName, outputFileName) {
  try {
    console.log(`📥 Exporting ${collectionName}...`);
    
    const snapshot = await db.collection(collectionName).get();
    const data = [];
    
    snapshot.forEach(doc => {
      data.push({
        id: doc.id,
        ...doc.data()
      });
    });
    
    const outputPath = path.join(__dirname, outputFileName);
    fs.writeFileSync(outputPath, JSON.stringify(data, null, 2));
    
    console.log(`✅ Successfully exported ${data.length} documents to ${outputFileName}`);
    process.exit(0);
  } catch (error) {
    console.error('❌ Export failed:', error);
    process.exit(1);
  }
}

// Export arrivalReports collection
exportCollection('arrivalReports', 'arrival_reports.json');
