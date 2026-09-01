package db

import "testing"

func TestPasswordEmailCryptoRequiresTheSamePasswordAndSalt(t *testing.T) {
	t.Parallel()

	crypto := passwordEmailCrypto{}
	ciphertext, salt, err := crypto.encrypt("person@example.com", "CurrentPass1@")
	if err != nil {
		t.Fatalf("encrypt() error = %v", err)
	}

	decrypted, err := crypto.decrypt(ciphertext, salt, "CurrentPass1@")
	if err != nil {
		t.Fatalf("decrypt() error = %v", err)
	}
	if decrypted != "person@example.com" {
		t.Fatalf("decrypt() = %q", decrypted)
	}
	if _, err := crypto.decrypt(ciphertext, salt, "WrongPass1@"); err == nil {
		t.Fatal("decrypt() succeeded with the wrong password")
	}

	otherCiphertext, otherSalt, err := crypto.encrypt("person@example.com", "NextPass1@")
	if err != nil {
		t.Fatalf("encrypt() error = %v", err)
	}
	if string(salt) == string(otherSalt) {
		t.Fatal("encrypt() reused the per-user salt")
	}
	if string(ciphertext) == string(otherCiphertext) {
		t.Fatal("encrypt() reused the ciphertext")
	}
}
