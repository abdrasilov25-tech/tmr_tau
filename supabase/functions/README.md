# Edge Functions: In-App Purchase валидация

Функции для серверной обработки покупок из App Store / Google Play:

- `verifyPurchase`
- `updateUserPremium`
- `updateBoostStatus`

Клиент Flutter вызывает только эти функции после успешного события IAP.
Бизнес-логика активации premium/boost выполняется на сервере.
