# Diagnostic PC (Windows)

Script qui vérifie l'état d'un PC Windows 10/11 et écrit un rapport sur le Bureau.
Il **ne modifie rien** : il lit seulement des informations.

## Utilisation

1. Sur GitHub, cliquez sur **Code > Download ZIP**, puis décompressez le dossier
   (clic droit > **Extraire tout**). Ne lancez pas le fichier depuis
   l'intérieur du ZIP : il ne trouverait pas le script.
2. Double-cliquez sur **`Lancer-Diagnostic.bat`** et acceptez la demande
   « Voulez-vous autoriser cette application… » (droits administrateur).
   Si Windows affiche « Windows a protégé votre ordinateur », cliquez sur
   **Informations complémentaires > Exécuter quand même**.
3. Attendez environ 1 minute. Le rapport `Diagnostic_PC_<date>.txt` s'ouvre
   dans le Bloc-notes et reste enregistré sur le Bureau.

## Ce qui est vérifié

- Système : version de Windows (fin du support de Windows 10), durée depuis le dernier redémarrage
- Processeur et mémoire : charge, RAM utilisée et installée
- Disques : santé, usure, erreurs de lecture, température, espace libre
- Plantages sur 30 jours : écrans bleus, arrêts brutaux, erreurs matérielles, erreurs disque, programmes qui plantent
- Erreurs du journal système sur 7 jours
- Intégrité des fichiers de Windows
- Mises à jour Windows et redémarrage en attente
- Antivirus, menaces détectées, pare-feu
- Périphériques en erreur (pilotes)
- Température et état de la batterie, si le PC les fournit
- Programmes au démarrage, programmes gourmands en mémoire
- Connexion Internet et DNS
- Fichiers temporaires

Le rapport commence par un **résumé** classé en CRITIQUE / ATTENTION / CONSEIL,
suivi des détails.
