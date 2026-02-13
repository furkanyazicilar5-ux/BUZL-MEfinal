bool isTurkish = true;

void toggleLanguage() {
  isTurkish = !isTurkish;
}

String trEn(String tr, String en) {
  return isTurkish ? tr : en;
}