-- 1. 교수 정보 뷰 생성
CREATE VIEW PROF_INFO AS
SELECT prof.id  AS 교수코드, prof.name AS 교수, prof.email  AS 이메일, dept.name AS 학부,dept.field AS 부서
FROM PROFESSOR prof RIGHT JOIN DEPARTMENT dept
ON prof.dept_id = dept.id 
ORDER BY prof.id DESC;

SELECT * from PROF_INFO;

DROP VIEW PROF_INFO;

-- 2. 수강 신청 정보 뷰 생성
CREATE VIEW REG_LIST AS
SELECT reg.id AS 고유번호, stu.id AS 학번, stu.name AS 학생이름, dept.name AS 학부, 
	   sub.id AS 강의코드,sub.name AS 강의, prof.name AS 교수, 
	   sub.point AS 학점, reg.rereg - 1 AS 재수강횟수, reg.date AS 신청일자
FROM registration AS reg left JOIN STUDENT AS stu ON reg.stu_id = stu.id
    LEFT JOIN SUBJECT AS sub ON reg.sub_id  = sub.id
    LEFT JOIN DEPARTMENT AS dept ON stu.dept_id = dept.id
    LEFT JOIN PROFESSOR AS prof ON sub.prof_id = prof.id 
ORDER BY stu_id DESC;

SELECT * from REG_LIST;

DROP VIEW REG_LIST;


-- 3. 수강 신청 프로시저 : 월로 학기를 나누고 재수강 신청일 경우 재수강 신청 카운트를 1추가, 
-- 신규 수강신청일 경우 디폴트값 대입
-- REGISTRATION 테이블 생성시, 유니크 처리를 했기에 재수강이 아닌 동일 학번, 동일 강의는 신청 불가하게 처리
DELIMITER //
CREATE PROCEDURE CREATE_REG (
v_stu_id INT, v_sub_id INT
)
BEGIN
    DECLARE term, stu_idx, sub_idx, max_rereg  INT;
    CASE 
		WHEN MONTH(sysdate()) between 3 and 6 THEN 
			set term = 1;
		WHEN MONTH(sysdate()) between 9 and 12 THEN 
			set term = 2;
		ELSE set term = 0;
	END CASE;

	SELECT stu_id, sub_id, MAX(rereg)
	INTO stu_idx, sub_idx, max_rereg
	FROM REGISTRATION
    GROUP BY stu_id, sub_id, fixed
    HAVING stu_id = v_stu_id AND sub_id = v_sub_id AND fixed = 1;
    
    IF max_rereg IS NULL THEN
		INSERT INTO registration(`stu_id`, `year`, `term`, `sub_id`, `date`) VALUES(v_stu_id, YEAR(sysdate()), term, v_sub_id, sysdate());
	ELSE
		INSERT INTO registration(`stu_id`, `year`, `term`, `sub_id`, `rereg`, `date`) VALUES(v_stu_id, YEAR(sysdate()), term, v_sub_id, max_rereg + 1, sysdate());
    END IF;
END//
DELIMITER ;

CALL CREATE_REG(20191003,4003);
DROP PROCEDURE CREATE_REG;

-- 4. 수강 취소 프로시저
SELECT * FROM REGISTRATION;

DELIMITER //
CREATE PROCEDURE CANCLE_REG (
v_id INT
)
BEGIN
 	DELETE FROM REGISTRATION WHERE id = v_id;
END //
DELIMITER ;

CALL CANCLE_REG(11);
DROP PROCEDURE CANCLE_REG;


-- 5. 교수의 학생 성적 입력 프로시저
SELECT * from PROF_INFO;
SELECT * FROM REG_LIST WHERE 교수 = '최종주';

DELIMITER //
CREATE PROCEDURE INPUT_GRADE (
v_id int, v_grade int
)
BEGIN
	UPDATE REGISTRATION
    SET reg = v_grade, fixed = 1
    WHERE id = v_id;
END //
DELIMITER ;

CALL INPUT_GRADE(2, 95);
SELECT * FROM REGISTRATION;
DROP PROCEDURE INPUT_GRADE;



-- 6. REGISTRATION 테이블 내용 삭제 백업 트리거
DROP TABLE BACKUP_REGISTRATION;

CREATE TABLE BACKUP_REGISTRATION(
  id INT,
  stu_id INT(10),
  year CHAR(4),
  term INT(1),
  sub_id INT(5),
  grade FLOAT,
  fixed INT(1),
  rereg INT(1),
  date DATETIME,
  backup_time DATE
);

SELECT * FROM BACKUP_REGISTRATION;

DELIMITER //
CREATE TRIGGER BACKUP_TRIGGER
AFTER DELETE
ON REGISTRATION
FOR EACH ROW 
BEGIN 
	INSERT INTO BACKUP_REGISTRATION VALUES ( 
	OLD.id, OLD.stu_id, OLD.year, OLD.term, OLD.sub_id,
	OLD.grade, OLD.fixed, OLD.rereg, OLD.date, sysdate());
END //
DELIMITER ;

SELECT * FROM REGISTRATION;

CALL CANCLE_REG(10);

SELECT * FROM BACKUP_REGISTRATION;

DROP TRIGGER BACKUP_TRIGGER;


-- 7. 백업된 REGISTRATION을 Rollback하는 프로시저 
DELIMITER //
CREATE PROCEDURE ROLLBACK (
v_id INT
)
BEGIN
	set sql_safe_updates = 0;
    
    INSERT INTO REGISTRATION 
	SELECT id, stu_id, year, term, sub_id, grade, fixed, rereg, date
	FROM BACKUP_REGISTRATION
    WHERE id = v_id;
    DELETE FROM BACKUP_REGISTRATION WHERE id = v_id;
END//
DELIMITER ;

CALL ROLLBACK(10);
SELECT * FROM BACKUP_REGISTRATION;
SELECT * FROM REGISTRATION;

DROP PROCEDURE ROLLBACK;

-- 8. 잘못된 교과목 코드 insert시 오류 문장 뜨게 하는 트리거
DELIMITER //
CREATE TRIGGER WRONG_INSERT
BEFORE INSERT 
ON REGISTRATION
FOR EACH ROW
BEGIN 
	IF ( NEW.sub_code) NOT BETWEEN 4001 AND 4010 THEN
		SIGNAL SQLSTATE '02100' SET MESSAGE_TEXT = '교과목 코드가 잘못 입력되었습니다. 다시 입력해주세요!';
 	END IF;
END //
DELIMITER ;

SELECT * FROM REGISTRATION;

CALL CREATE_REG(20221312,4011);

DROP TRIGGER WRONG_INSERT;


-- 9. 여석(spare)을 카운팅하여 그 이상이 될 경우 신청 불가하게 만드는 트리거
DELIMITER //
CREATE TRIGGER LEFT_COUNT 
BEFORE INSERT ON REGISTRATION
FOR EACH ROW
BEGIN
	DECLARE counted INT;
	DECLARE spared INT;

	SELECT COUNT(*)
	INTO counted
	FROM REGISTRATION
	group by sub_code
	having new.sub_code = sub_code;
    
    SELECT spare
	INTO spared
	FROM SUBJECT
	WHERE NEW.sub_code = sub_code;
	
	IF counted > spared THEN
		SIGNAL SQLSTATE '02000' SET MESSAGE_TEXT = '여석이 존재하지 않습니다.';
	END IF;

END //
DELIMITER ;

-- 10. 수강 시간 이외에 신청시 오류 메시지 
SELECT sysdate() FROM DUAL;
SELECT DATE_FORMAT(sysdate(), '%H:%i') FROM DUAL;

DROP TRIGGER WRONG_TIME;

DELIMITER //
CREATE TRIGGER WRONG_TIME
BEFORE INSERT 
ON REGISTRATION
FOR EACH ROW
BEGIN 
	IF (DATE_FORMAT(sysdate(), '%H:%i') NOT BETWEEN '9:00' AND '13:00') THEN
		SIGNAL SQLSTATE '02200' SET MESSAGE_TEXT = '수강신청 시간이 아닙니다.';
	END IF;
END //
DELIMITER ;

CALL CREATE_REG(20221312,4010);

SELECT * FROM REGISTRATION;

-- 11. 학생마다 성적에 따라 신청 학점이 정해져있는 트리거
DELIMITER //
CREATE TRIGGER LIMIT_REG
BEFORE INSERT 
ON REGISTRATION
FOR EACH ROW
BEGIN
	DECLARE sum_point INT;
	DECLARE d_grade FLOAT;

	SELECT grade 
    INTO d_grade
    FROM STUDENT
    WHERE id = NEW.stu_id;
   
	SELECT sum(point)
	INTO sum_point
	FROM REGISTRATION reg LEFT JOIN SUBJECT sub ON reg.sub_id = sub.id
    where stu_id = NEW.stu_id and fixed = 0;
   
    IF d_grade >= 4 then
    	IF sum_point > 24  THEN
			SIGNAL SQLSTATE '02100' SET MESSAGE_TEXT = '수강 가능한 학점을 넘겼습니다.';
		END IF;
	
	else 
		IF sum_point > 18  THEN
			SIGNAL SQLSTATE '02100' SET MESSAGE_TEXT = '수강 가능한 학점을 넘겼습니다.';
		END IF;
	END IF;
END; //
DELIMITER ;

DROP TRIGGER LIMIT_REG;

-- 12. 수강신청 한 학생들 중에서 서울에 사는 사람의 학점
SELECT DISTINCT stu.id, name, address, exam_avg
FROM STUDENT stu INNER JOIN SCORE scr ON stu.id = scr.stu_id
			   INNER JOIN REGISTRATION reg ON stu.id = reg.stu_id 
WHERE address = '서울'
ORDER BY exam_avg DESC;





   
   
   
   

