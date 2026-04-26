# Deploy notes

MySQL 8.0 container. `flags` table (1 row) readable by the app user.
Error suppression at app layer. Max query timeout set to 10s to bound
wasteful sleeps.
