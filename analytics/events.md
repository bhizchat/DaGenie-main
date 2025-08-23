# Analytics Event Taxonomy

| Event Name       | Parameters                                         | Description                                | Owner          |
|------------------|----------------------------------------------------|--------------------------------------------|----------------|
| generate_plan    | uid, location, preferences, budget, timeOfDay, planCount, createdAt | Fired when backend generates date plans. Captures context for retention and funnel analysis. | Backend (Cloud Functions) |
| plan_saved       | uid, planId, createdAt                             | Fired when user saves a plan.              | iOS frontend   |
| romance_points_earned | uid, planId, points, createdAt                 | Fired after `awardRomancePoints` callable succeeds. | Backend / iOS |
| subscription_purchase | uid, productId, price, currency, createdAt    | Fired on successful receipt validation.    | Backend        |
| app_launch       | uid (optional), appVersion, device, createdAt      | Generic mobile app launch event.           | iOS frontend   |

Add new events here and keep parameters camelCase.  Update associated tests under `tests/analytics`.
