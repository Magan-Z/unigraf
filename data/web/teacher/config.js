// Адрес общего сервера и публичный ключ проекта: они же вшиты в приложение и не секретны (доступ защищён на сервере).
// Расписание (index.json, groups/*.json) страница берёт с этого же сайта: siteBase — путь от /teacher/ к корню сайта.
window.UNIGRAF_TEACHER = {
  api: 'https://ktavbvmeohtwzdoptueq.supabase.co',
  key: 'sb_publishable_dYboAghNJ7NXFp6lF5prSA_GspY9-p7',
  siteBase: '../'
};
