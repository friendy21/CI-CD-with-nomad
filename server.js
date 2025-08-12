const express = require('express');
const app = express();
const port = process.env.PORT || 3000; // Changed from 8000 to 3000

app.get('/health', (_, res) => res.json({ status: 'ok', timestamp: new Date().toISOString() }));
app.get('/ready', (_, res) => res.json({ ready: true }));
app.get('/', (_, res) => res.send('Hello from CI/CD + Nomad! Version: ' + process.env.VERSION || '1.0.0'));

app.listen(port, '0.0.0.0', () => {
    console.log(`App listening on 0.0.0.0:${port}`);
});
