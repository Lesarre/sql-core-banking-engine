/*
======================================================================
PROJE: CORE BANKING ENGINE & FRAUD DETECTION
Açıklama: Bankacılık işlemleri, ACID uyumlu para transferleri, 
          şüpheli işlem tespiti (Trigger) ve KVKK/GDPR veri maskeleme.
======================================================================
*/

-- 0. VERİTABANI OLUŞTURMA
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'CoreBankingDB')
BEGIN
    CREATE DATABASE CoreBankingDB;
END


USE CoreBankingDB;


-- 1. TABLOLARIN OLUŞTURULMASI VE KVKK VERİ MASKELEME (DDM)
IF OBJECT_ID('dbo.BlockedTransactions', 'U') IS NOT NULL DROP TABLE dbo.BlockedTransactions;
IF OBJECT_ID('dbo.AccountTransactions', 'U') IS NOT NULL DROP TABLE dbo.AccountTransactions;
IF OBJECT_ID('dbo.Accounts', 'U') IS NOT NULL DROP TABLE dbo.Accounts;
GO

CREATE TABLE Accounts (
    AccountID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    AccountNumber VARCHAR(20) UNIQUE NOT NULL,
    Balance DECIMAL(18,2) NOT NULL CONSTRAINT CHK_Balance_NonNegative CHECK (Balance >= 0),
    IsActive BIT DEFAULT 1,
    
    -- KVKK Kapsamında Maskelenmiş Kolonlar (Dynamic Data Masking)
    TCKN VARCHAR(11) MASKED WITH (FUNCTION = 'partial(2, "******", 3)') NULL,
    PhoneNumber VARCHAR(15) MASKED WITH (FUNCTION = 'default()') NULL,
    Email VARCHAR(100) MASKED WITH (FUNCTION = 'email()') NULL,
    
    CreatedAt DATETIME DEFAULT GETDATE()
);


CREATE TABLE AccountTransactions (
    TransactionID INT IDENTITY(1,1) PRIMARY KEY,
    SenderAccountID INT NOT NULL,
    ReceiverAccountID INT NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    TransactionDate DATETIME DEFAULT GETDATE(),
    TransactionStatus VARCHAR(20) NOT NULL,
    ErrorMessage NVARCHAR(250) NULL,
    FOREIGN KEY (SenderAccountID) REFERENCES Accounts(AccountID),
    FOREIGN KEY (ReceiverAccountID) REFERENCES Accounts(AccountID)
);


CREATE TABLE BlockedTransactions (
    BlockID INT IDENTITY(1,1) PRIMARY KEY,
    TransactionID INT NULL,
    SenderAccountID INT NOT NULL,
    ReceiverAccountID INT NOT NULL,
    AttemptedAmount DECIMAL(18,2) NOT NULL,
    FraudReason NVARCHAR(250) NOT NULL,
    RiskScore INT NOT NULL,
    CreatedAt DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (SenderAccountID) REFERENCES Accounts(AccountID),
    FOREIGN KEY (ReceiverAccountID) REFERENCES Accounts(AccountID)
);


-- 2. TEST VERİLERİNİN EKLENMESİ
INSERT INTO Accounts (CustomerName, AccountNumber, Balance, TCKN, PhoneNumber, Email)
VALUES 
('Ali Yılmaz', 'TR10001', 5000.00, '12345678901', '05321234567', 'ali.yilmaz@ornekbank.com'),
('Veli Demir', 'TR10002', 1500.00, '98765432109', '05559876543', 'veli.demir@ornekbank.com');


-- 3. TRANSFER MOTORU (ACID & CONCURRENCY CONTROL)
CREATE OR ALTER PROCEDURE Sp_TransferMoney
    @SenderAccountNumber VARCHAR(20),
    @ReceiverAccountNumber VARCHAR(20),
    @Amount DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @SenderID INT, @ReceiverID INT, @SenderBalance DECIMAL(18,2);

    IF @Amount <= 0
    BEGIN
        RAISERROR('Transfer tutarı 0''dan büyük olmalıdır.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;
    BEGIN TRY
        SELECT @SenderID = AccountID, @SenderBalance = Balance
        FROM Accounts WITH (UPDLOCK, ROWLOCK)
        WHERE AccountNumber = @SenderAccountNumber AND IsActive = 1;

        SELECT @ReceiverID = AccountID
        FROM Accounts WITH (UPDLOCK, ROWLOCK)
        WHERE AccountNumber = @ReceiverAccountNumber AND IsActive = 1;

        IF @SenderID IS NULL OR @ReceiverID IS NULL
            RAISERROR('Gönderici veya alıcı hesap bulunamadı ya da hesap aktif değil.', 16, 1);
        IF @SenderID = @ReceiverID
            RAISERROR('Aynı hesaba transfer yapılamaz.', 16, 1);
        IF @SenderBalance < @Amount
            RAISERROR('Yetersiz bakiye! İşlem gerçekleştirilemedi.', 16, 1);

        UPDATE Accounts SET Balance = Balance - @Amount WHERE AccountID = @SenderID;
        UPDATE Accounts SET Balance = Balance + @Amount WHERE AccountID = @ReceiverID;

        INSERT INTO AccountTransactions (SenderAccountID, ReceiverAccountID, Amount, TransactionStatus)
        VALUES (@SenderID, @ReceiverID, @Amount, 'SUCCESS');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF @SenderID IS NOT NULL AND @ReceiverID IS NOT NULL
        BEGIN
            INSERT INTO AccountTransactions (SenderAccountID, ReceiverAccountID, Amount, TransactionStatus, ErrorMessage)
            VALUES (@SenderID, @ReceiverID, @Amount, 'FAILED', ERROR_MESSAGE());
        END
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@Err, 16, 1);
    END CATCH
END;
GO

-- 4. GÜVENLİK VE SAHTECİLİK (FRAUD DETECTION) TRIGGER'I
CREATE OR ALTER TRIGGER TRG_FraudDetection
ON AccountTransactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TransactionID INT, @SenderID INT, @ReceiverID INT, @CurrentAmount DECIMAL(18,2);
    DECLARE @RecentTxCount INT;

    SELECT @TransactionID = TransactionID, @SenderID = SenderAccountID, @ReceiverID = ReceiverAccountID, @CurrentAmount = Amount
    FROM inserted;

    -- Kural: Son 5 dakikada 3'ten fazla işlem var mı?
    SELECT @RecentTxCount = COUNT(*) FROM AccountTransactions
    WHERE SenderAccountID = @SenderID AND TransactionDate >= DATEADD(MINUTE, -5, GETDATE());

    IF @RecentTxCount > 3
    BEGIN
        INSERT INTO BlockedTransactions (TransactionID, SenderAccountID, ReceiverAccountID, AttemptedAmount, FraudReason, RiskScore)
        VALUES (@TransactionID, @SenderID, @ReceiverID, @CurrentAmount, 'Kısa süre içinde olağanüstü işlem sıklığı.', 85);

        UPDATE Accounts SET IsActive = 0 WHERE AccountID = @SenderID;
    END
END;


-- 5. HESAP BLOKE KALDIRMA OPERASYONU
CREATE OR ALTER PROCEDURE Sp_UnblockAccount
    @AccountNumber VARCHAR(20),
    @AdminNote NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TargetAccountID INT;

    SELECT @TargetAccountID = AccountID FROM Accounts WHERE AccountNumber = @AccountNumber;
    
    IF @TargetAccountID IS NULL
    BEGIN
        RAISERROR('Belirtilen hesap bulunamadı.', 16, 1);
        RETURN;
    END

    UPDATE Accounts SET IsActive = 1 WHERE AccountID = @TargetAccountID;
    
    ;WITH LastBlockedRecord AS (
        SELECT TOP (1) FraudReason FROM BlockedTransactions
        WHERE SenderAccountID = @TargetAccountID ORDER BY BlockID DESC
    )
    UPDATE LastBlockedRecord
    SET FraudReason = FraudReason + ' | [AÇILDI: ' + @AdminNote + ']';
END;
