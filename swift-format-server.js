import { watch } from 'fs';
import { exec } from 'child_process';
import { resolve, join, dirname } from 'path';
import { fileURLToPath } from 'url';

// The directory to watch (your project directory)
const projectDir = resolve(dirname(fileURLToPath(import.meta.url)));

console.log(`Watching directory: ${projectDir}`);

// Function to run swift-format
const formatFile = (filePath) => {
  exec(`swift-format --in-place ${filePath}`, (err, stdout, stderr) => {
    if (err) {
      console.error(`Error formatting ${filePath}: ${stderr}`);
      return;
    }
    console.log(`Formatted ${filePath}`);
  });
};

// Watch the project directory for file changes
watch(projectDir, { recursive: true }, (eventType, filename) => {
  if (filename && filename.endsWith('.swift')) {
    const filePath = join(projectDir, filename);
    console.log(`File ${eventType}: ${filePath}`);
    formatFile(filePath);  // Run swift-format on the changed file
  }
});

console.log('File watcher is running...');
