const express = require('express');
const app = express();
const port = process.env.PORT || 8000;

app.get('/health', (_, res) => res.json({ status: 'ok' }));
app.get('/', (_, res) => res.send('Hello from CI/CD + Nomad!'));

app.listen(port, () => console.log(`App listening on ${port}`));
