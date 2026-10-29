-- Library Management System (MySQL 8.0+)
-- Complete single-script project for MySQL Workbench.
-- IMPORTANT: This script DROPS and recreates library_management_db.
-- Save any existing data before running. Execute the entire script once on a fresh setup.

DROP DATABASE IF EXISTS library_management_db;
CREATE DATABASE library_management_db;
USE library_management_db;

-- =========================================================
-- PART A: TABLE CREATION
-- =========================================================

CREATE TABLE books (
    book_id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(150) NOT NULL,
    author VARCHAR(100) NOT NULL,
    category VARCHAR(50) DEFAULT 'General',
    total_copies INT NOT NULL DEFAULT 1,
    available_copies INT NOT NULL DEFAULT 1,
    CONSTRAINT chk_book_total CHECK (total_copies >= 0),
    CONSTRAINT chk_book_available CHECK (
        available_copies >= 0 AND available_copies <= total_copies
    )
);

CREATE TABLE students (
    student_id INT AUTO_INCREMENT PRIMARY KEY,
    roll_no VARCHAR(20) NOT NULL UNIQUE,
    student_name VARCHAR(100) NOT NULL,
    department VARCHAR(60) NOT NULL,
    email VARCHAR(100) UNIQUE,
    phone VARCHAR(15)
);

CREATE TABLE librarians (
    librarian_id INT AUTO_INCREMENT PRIMARY KEY,
    librarian_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE
);

CREATE TABLE book_issues (
    issue_id INT AUTO_INCREMENT PRIMARY KEY,
    book_id INT NOT NULL,
    student_id INT NOT NULL,
    librarian_id INT NOT NULL,
    issue_date DATE NOT NULL,
    due_date DATE NOT NULL,
    return_date DATE DEFAULT NULL,
    status ENUM('Issued', 'Returned') NOT NULL DEFAULT 'Issued',
    CONSTRAINT fk_issue_book FOREIGN KEY (book_id) REFERENCES books(book_id),
    CONSTRAINT fk_issue_student FOREIGN KEY (student_id) REFERENCES students(student_id),
    CONSTRAINT fk_issue_librarian FOREIGN KEY (librarian_id) REFERENCES librarians(librarian_id),
    CONSTRAINT chk_issue_dates CHECK (due_date >= issue_date)
);

CREATE INDEX idx_book_issues_status ON book_issues(status);
CREATE INDEX idx_book_issues_student ON book_issues(student_id);

-- =========================================================
-- PART B: SAMPLE DATA
-- =========================================================

INSERT INTO books (title, author, category, total_copies, available_copies) VALUES
('Database System Concepts', 'Abraham Silberschatz', 'Database', 5, 5),
('The Great Gatsby', 'F. Scott Fitzgerald', 'Fiction', 3, 3),
('To Kill a Mockingbird', 'Harper Lee', 'Fiction', 4, 4),
('Introduction to Python', 'Mark Lutz', 'Programming', 6, 6),
('Atomic Habits', 'James Clear', 'Self-Help', 4, 4);

INSERT INTO students (roll_no, student_name, department, email, phone) VALUES
('IT001', 'Aarav Sharma', 'Information Technology', 'aarav.sharma@example.com', '9876500001'),
('IT002', 'Ananya Verma', 'Information Technology', 'ananya.verma@example.com', '9876500002'),
('IT003', 'Rohan Patil', 'Computer Engineering', 'rohan.patil@example.com', '9876500003'),
('IT004', 'Priya Kulkarni', 'Information Technology', 'priya.kulkarni@example.com', '9876500004'),
('IT005', 'Neha Joshi', 'Electronics', 'neha.joshi@example.com', '9876500005');

INSERT INTO librarians (librarian_name, email) VALUES
('Suresh Deshmukh', 'suresh.librarian@example.com');

-- =========================================================
-- PART C: VIEW
-- =========================================================

CREATE VIEW issue_details AS
SELECT
    bi.issue_id,
    b.book_id,
    b.title AS book_title,
    s.student_id,
    s.roll_no,
    s.student_name,
    l.librarian_name,
    bi.issue_date,
    bi.due_date,
    bi.return_date,
    bi.status,
    CASE
        WHEN bi.status = 'Issued' AND bi.due_date < CURDATE() THEN 'Overdue'
        WHEN bi.status = 'Issued' THEN 'Not Returned'
        ELSE 'Returned'
    END AS issue_status
FROM book_issues bi
JOIN books b ON bi.book_id = b.book_id
JOIN students s ON bi.student_id = s.student_id
JOIN librarians l ON bi.librarian_id = l.librarian_id;

-- =========================================================
-- PART D: PROCEDURES
-- =========================================================

DELIMITER $$

CREATE PROCEDURE IssueBook(
    IN p_book_id INT,
    IN p_student_id INT,
    IN p_librarian_id INT
)
BEGIN
    DECLARE v_available INT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT available_copies
      INTO v_available
      FROM books
     WHERE book_id = p_book_id
     FOR UPDATE;

    IF v_available IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Book does not exist';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM students WHERE student_id = p_student_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Student does not exist';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM librarians WHERE librarian_id = p_librarian_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Librarian does not exist';
    END IF;

    IF v_available <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No copies available';
    END IF;

    INSERT INTO book_issues
        (book_id, student_id, librarian_id, issue_date, due_date, status)
    VALUES
        (p_book_id, p_student_id, p_librarian_id,
         CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY), 'Issued');

    UPDATE books
       SET available_copies = available_copies - 1
     WHERE book_id = p_book_id;

    COMMIT;
END$$

CREATE PROCEDURE ReturnBook(IN p_issue_id INT)
BEGIN
    DECLARE v_book_id INT DEFAULT NULL;
    DECLARE v_status VARCHAR(20) DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT book_id, status
      INTO v_book_id, v_status
      FROM book_issues
     WHERE issue_id = p_issue_id
     FOR UPDATE;

    IF v_book_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Issue record does not exist';
    END IF;

    IF v_status = 'Returned' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'This book has already been returned';
    END IF;

    UPDATE book_issues
       SET status = 'Returned',
           return_date = CURDATE()
     WHERE issue_id = p_issue_id;

    UPDATE books
       SET available_copies = available_copies + 1
     WHERE book_id = v_book_id;

    COMMIT;
END$$

DELIMITER ;

-- =========================================================
-- PART E: TRIGGER
-- =========================================================

DELIMITER $$

CREATE TRIGGER before_book_issue_insert
BEFORE INSERT ON book_issues
FOR EACH ROW
BEGIN
    IF NEW.due_date < NEW.issue_date THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Due date cannot be before issue date';
    END IF;
END$$

DELIMITER ;

-- =========================================================
-- PART F: BASIC VERIFICATION QUERIES
-- =========================================================

SHOW TABLES;

DESCRIBE books;
DESCRIBE students;
DESCRIBE librarians;
DESCRIBE book_issues;

SELECT * FROM books;
SELECT * FROM students;
SELECT * FROM librarians;
SELECT * FROM book_issues;

-- =========================================================
-- PART G: SEARCH AND FILTER QUERIES
-- =========================================================

-- 1. Search for a title containing Python
SELECT * FROM books
WHERE title LIKE '%Python%';

-- 2. List books in the Fiction category
SELECT * FROM books
WHERE category = 'Fiction';

-- 3. Show books that are currently available
SELECT book_id, title, author, available_copies
FROM books
WHERE available_copies > 0;

-- 4. Search students from Information Technology
SELECT * FROM students
WHERE department = 'Information Technology';

-- 5. Find a student by roll number
SELECT * FROM students
WHERE roll_no = 'IT001';

-- =========================================================
-- PART H: JOINS, AGGREGATES, AND REPORTS
-- =========================================================

-- 1. Total number of books/titles
SELECT COUNT(*) AS total_book_titles
FROM books;

-- 2. Total physical copies in the library
SELECT SUM(total_copies) AS total_physical_copies
FROM books;

-- 3. Total available copies
SELECT SUM(available_copies) AS total_available_copies
FROM books;

-- 4. Total students
SELECT COUNT(*) AS total_students
FROM students;

-- 5. Count books by category
SELECT category, COUNT(*) AS number_of_titles,
       SUM(total_copies) AS physical_copies
FROM books
GROUP BY category;

-- 6. List issue details using the view
SELECT * FROM issue_details;

-- 7. List books issued by each student
SELECT s.student_name, b.title, bi.issue_date, bi.due_date, bi.status
FROM book_issues bi
JOIN students s ON bi.student_id = s.student_id
JOIN books b ON bi.book_id = b.book_id
ORDER BY bi.issue_date DESC;

-- 8. Count currently issued books
SELECT COUNT(*) AS active_issues
FROM book_issues
WHERE status = 'Issued';

-- 9. List overdue books
SELECT * FROM issue_details
WHERE status = 'Issued' AND due_date < CURDATE();

-- 10. Find students who have never borrowed a book
SELECT s.student_id, s.student_name
FROM students s
LEFT JOIN book_issues bi ON s.student_id = bi.student_id
WHERE bi.issue_id IS NULL;

-- =========================================================
-- PART I: DEMONSTRATE ISSUE AND RETURN
-- These are example operations. Run each only when you want
-- to change the sample data.
-- =========================================================

-- Issue book 1 to student 1, handled by librarian 1:
-- CALL IssueBook(1, 1, 1);

-- Check the issue record and updated book availability:
-- SELECT * FROM issue_details;
-- SELECT book_id, title, total_copies, available_copies FROM books;

-- Return issue record 1 (replace 1 with an existing issue_id):
-- CALL ReturnBook(1);

-- Check the updated status and availability:
-- SELECT * FROM issue_details;
-- SELECT book_id, title, total_copies, available_copies FROM books;

-- =========================================================
-- PART J: UPDATE AND DELETE EXAMPLES
-- Uncomment and run these only when you want to change data.
-- =========================================================

-- UPDATE books SET category = 'Technology' WHERE book_id = 1;
-- UPDATE students SET phone = '9999999999' WHERE student_id = 1;
-- DELETE FROM students WHERE student_id = 5; -- only if no issue references them

-- =========================================================
-- END OF LIBRARY MANAGEMENT SYSTEM
-- =========================================================
