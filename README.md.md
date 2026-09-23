# 🏦 SQL Core Banking & Fraud Detection Engine

Bu proje, bankacılık veri tabanlarında uçtan uca işlem güvenliği (ACID), sahtecilik tespiti (Fraud Detection) ve veri gizliliği (KVKK/GDPR) kurallarını SQL Server (T-SQL) üzerinde simüle eden kurumsal düzeyde bir veri mimarisi çalışmasıdır.

## 🚀 Proje Modülleri ve Yetenekler

### 1. İşlem Motoru (Transaction Engine)
* **ACID Prensipleri & Hata Yönetimi:** `Sp_TransferMoney` prosedürü `TRY-CATCH` blokları ve `BEGIN/COMMIT/ROLLBACK TRANSACTION` kullanarak veri tutarlılığını garanti eder. Kısmi işlemleri ve para kayıplarını engeller.
* **Eşzamanlılık (Concurrency Control):** Deadlock ve veri ezilmesini (Dirty Read) önlemek için tablolara okuma anında `UPDLOCK, ROWLOCK` hintleri uygulanmıştır.

### 2. Şüpheli İşlem ve Güvenlik Duvarı (Fraud Detection)
* **Kural Tabanlı Trigger Algoritması:** `AFTER INSERT` trigger'ı (`TRG_FraudDetection`), hesaptan son 5 dakika içinde anomali yaratacak sıklıkta (spam) para çıkışı yapıldığında işlemi tespit eder.
* **Otomatik Aksiyon:** Şüpheli hesap anında pasife çekilir (`IsActive = 0`) ve vaka analizi için `BlockedTransactions` tablosuna risk skoru ile birlikte loglanır.
* **Güvenlik Operasyonu:** Müşteri teyidi alındığında `Sp_UnblockAccount` prosedürü ve CTE (Common Table Expressions) kullanılarak hesap blokesi güvenli bir şekilde kaldırılır.

### 3. Veri Gizliliği (Dynamic Data Masking - DDM)
* **KVKK/GDPR Uyumu:** `Accounts` tablosunda bulunan hassas müşteri verileri (TC Kimlik, Telefon, E-posta) SQL Server'ın **Dynamic Data Masking** özelliği ile maskelenmiştir. 
* Yetkisiz personelin sorgularında bu veriler anlık olarak sansürlenerek listelenir (Örn: `12******901`).

## 🛠 Kullanılan Teknolojiler
* **RDBMS:** MS SQL Server (T-SQL)
* **Veritabanı Nesneleri:** Stored Procedures, Triggers, DDL/DML, Foreign Keys, Constraints, CTEs
* **Güvenlik:** Dynamic Data Masking, T-SQL Error Handling (TRY-CATCH, RAISERROR)

## ⚙️ Kurulum
Projeyi test etmek için ekstra bir ayar yapmanıza gerek yoktur. `CoreBanking_Setup.sql` dosyasını SSMS (SQL Server Management Studio) üzerinde açıp çalıştırmanız yeterlidir. Script, `CoreBankingDB` adında yeni bir veritabanı oluşturup tüm mimariyi otomatik olarak kuracaktır.