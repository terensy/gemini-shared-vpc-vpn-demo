# 用 gcloud ADC(Application Default Credentials)認證,程式碼裡不放任何憑證。
# 執行前請先 `gcloud auth application-default login`。
provider "google" {}
